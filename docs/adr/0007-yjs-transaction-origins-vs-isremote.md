# 0007: Yjs Transaction Origins vs isRemote Flag

## Status
Accepted

## Context
In our local-first architecture, the `SyncService` pulls Yjs updates from the backend and applies them to the local `YDoc`. The `YjsDocEditorBridge` listens to the `YDoc` and synchronizes these changes with the Flutter `SuperEditor`.
Simultaneously, `SuperEditor` registers local typing changes and flushes them to the `YDoc`.

When a remote update is applied via `applyUpdate(doc, serverUpdate)`, the Yjs observer (`nodesMap.observe`) triggers. To prevent the UI layer (`NoteEditorProvider`) from assuming this was a local user edit and incorrectly marking the note as `isDirty = true` (which causes an infinite sync ping-pong loop), the system needs to distinguish between **local** and **remote** changes.

## Decision
We decided to use an explicit `isRemote` boolean flag passed through the `onDocChanged` callback rather than relying on native Yjs `transactionOrigin`.

```dart
// YjsDocEditorBridge.dart
_onDocChanged?.call(isRemote: true); // for remote syncs
_onDocChanged?.call(isRemote: false); // for local flushes and local metadata edits
```

## Rationale
Using the native Yjs `transactionOrigin` (e.g., `doc.transact(..., origin: 'local')` and `applyUpdate(..., transactionOrigin: 'remote')`) is the mathematically and canonically correct approach for CRDTs.

However, the architecture of `YjsDocEditorBridge` combined with `SuperEditor` introduces structural peculiarities that make transaction origins highly invasive:

1. **Callback Abstraction Boundary**: `NoteEditorProvider` (the controller that manages SQLite persistence and `isDirty` flags) does not listen to `doc.onUpdate` directly. It listens to the `YjsDocEditorBridge` via the `onDocChanged` callback. To use transaction origins, we would need to expose the raw Yjs update stream through the bridge, forcing the Flutter UI layer to understand Yjs transactions.
2. **Asynchronous UI Reactions**: `SuperEditor` has an internal reaction pipeline (e.g., converting `---` into a divider). When a remote sync modifies the editor, these reactions can fire asynchronously *after* the remote transaction has completed, triggering new local flushes. 
3. **Implicit Remote Routing**: `YjsDocEditorBridge` currently uses internal flags (`_isFlushingLocal`) to decide whether a `nodesMap.observe` event should be treated as a remote UI update.

The `isRemote` boolean perfectly encapsulates the concept of a transaction origin but adapts it to the existing synchronous callback contract (`onDocChanged`) without requiring a complete rewrite of the bridge's state machine.

## Consequences
- **Positive**: The infinite 89-byte ping-pong sync loop is broken without major architectural rewrites.
- **Positive**: The `NoteEditorProvider` debouncer correctly accumulates local edits while ignoring remote noise.
- **Negative**: The concept of "origin" leaks slightly into the UI callbacks, meaning any new feature that mutates the `YDoc` directly (like `updateTaskMetadataInYDoc`) must explicitly declare `isRemote: false`.
