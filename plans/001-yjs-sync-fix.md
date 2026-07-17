# Plan 001: Implement fallback for corrupted Yjs text nodes and await SQLite projection

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat e567d80..HEAD -- lib/features/notes/domain/yjs_doc_editor_bridge.dart lib/features/notes/domain/yjs_node_codec.dart lib/features/notes/presentation/controllers/note_editor_provider.dart`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: MED
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `e567d80`, 2026-07-17

## Why this matters

The `yjs_dart` library has a bug where uninitialized root types are silently converted to dictionaries (`YMap`) instead of text (`YText`). This permanently corrupted existing text paragraphs in the user's database. When a user tries to edit an existing, corrupted note, the CRDT fails to save the text because it tries to use `getText()` on a `YMap`. This plan adds a fallback mechanism so that if `content/$id` is corrupted, the system seamlessly falls back to `content_fixed/$id`. It also ensures the local SQLite projection is fully awaited before disconnecting the WebSocket, preventing data loss when closing the app quickly.

## Current state

- `lib/features/notes/domain/yjs_doc_editor_bridge.dart` — CRDT bridge; fails silently on type mismatch for corrupted nodes.
- `lib/features/notes/domain/yjs_node_codec.dart` — Note decoding; fails to load text from corrupted nodes.
- `lib/features/notes/presentation/controllers/note_editor_provider.dart` — Editor initialization; does not await `projectNodes` correctly.

Excerpts:
`lib/features/notes/domain/yjs_doc_editor_bridge.dart` (around line 151):
```dart
    try {
      final sharedType = _doc.getText('content/$id');
      if (sharedType != null) {
        _updateYTextIncrementally(sharedType, text ?? '');
      }
    } catch (e) {
      dev.log('[YjsBridge] _serializeNode: failed to get content for $id (corrupted type)', name: 'YjsBridge', error: e);
    }
```

`lib/features/notes/presentation/controllers/note_editor_provider.dart` (around line 39):
```dart
            onDocChanged: () {
              yjsMgr.projectNodes(noteId);
              // Fire-and-forget: persist is async and serialized internally via
              // _persistLock. The YDoc state is already consistent at this
              // point; this write is a safety net so offline closures don't
              // lose edits. Riverpod's onDispose is sync and cannot await it.
              unawaited(yjsMgr.persist(noteId));
            },
```

## Commands you will need

| Purpose   | Command                  | Expected on success |
|-----------|--------------------------|---------------------|
| Check     | `dart analyze`           | exit 0, no errors in touched files   |
| Tests     | `flutter test test/features/notes/domain/`  | all pass |

## Scope

**In scope**:
- `lib/features/notes/domain/yjs_doc_editor_bridge.dart`
- `lib/features/notes/domain/yjs_node_codec.dart`
- `lib/features/notes/presentation/controllers/note_editor_provider.dart`

**Out of scope**:
- Modifications to backend sync logic.

## Git workflow

- Branch: `advisor/001-yjs-sync-fix`
- Commit message style: `fix(notes): implement fallback for corrupted yjs text nodes and await projection`

## Steps

### Step 1: Implement fallback in `_serializeNode`

In `lib/features/notes/domain/yjs_doc_editor_bridge.dart`, update `_serializeNode`'s try-catch block for `content/$id` to fall back to `content_fixed/$id` when a type exception occurs (i.e. the catch block).

```dart
    try {
      final sharedType = _doc.getText('content/$id');
      if (sharedType != null) {
        _updateYTextIncrementally(sharedType, text ?? '');
      }
    } catch (e) {
      dev.log('[YjsBridge] _serializeNode: content/$id is corrupted, falling back to content_fixed/$id', name: 'YjsBridge', error: e);
      final fallbackType = _doc.getText('content_fixed/$id');
      if (fallbackType != null) {
        _updateYTextIncrementally(fallbackType, text ?? '');
      }
    }
```

**Verify**: `dart analyze lib/features/notes/domain/yjs_doc_editor_bridge.dart` → exit 0, no errors.

### Step 2: Implement fallback in `_readNodeFromYMap` and `_readNodeFromJsonString`

In `lib/features/notes/domain/yjs_node_codec.dart`, modify both `_readNodeFromYMap` and `_readNodeFromJsonString` to check if `content_fixed/$id` exists and has length > 0. If it doesn't, fallback to `content/$id`. However, since `yjs_dart`'s `getText` returns an empty string if the property is missing, the best approach is to check if `content_fixed/$id`'s text is not empty. If both are empty, default to empty.

Update `_readNodeFromYMap` (around line 14):
```dart
  try {
    YText? sharedType;
    try {
      sharedType = doc.getText('content_fixed/$nodeId');
    } catch (_) {}
    
    if (sharedType == null || sharedType.toString().isEmpty) {
      try {
        sharedType = doc.getText('content/$nodeId');
      } catch (_) {}
    }

    if (sharedType != null) {
      textContent = sharedType.toString();
    }
    
    if (derivedType == 'task' || derivedType == 'corrupted') {
      // Validated
    }
  } catch (e) {
```
*Note: Make sure to apply the same logic to `_readNodeFromJsonString`.*

**Verify**: `dart analyze lib/features/notes/domain/yjs_node_codec.dart` → exit 0, no errors.

### Step 3: Await `projectNodes` during disposal

In `lib/features/notes/presentation/controllers/note_editor_provider.dart`, change the `onDocChanged` callback to return `Future<void>`.
Update the signature in `NoteEditorController` (`lib/features/notes/presentation/controllers/note_editor_controller.dart`) and `YjsDocEditorBridge` if necessary. However, `onDocChanged` is `VoidCallback` in the signatures.
Instead of changing the signature, we can track the `Future` returned by `projectNodes` in the provider, and await it during `ref.onDispose`.

In `lib/features/notes/presentation/controllers/note_editor_provider.dart`:
```dart
      Future<void>? _lastProjection;

      syncService?.connectNote(
        noteId,
        onReady: (doc, sendUpdate) {
          if (disposed) return;
          controller.initFromDoc(
            doc: doc,
            noteId: noteId,
            sendUpdate: sendUpdate,
            onDocChanged: () {
              _lastProjection = yjsMgr.projectNodes(noteId);
              unawaited(yjsMgr.persist(noteId));
            },
          );
        },
      );

      ref.onDispose(() {
        disposed = true;
        unawaited(
          controller.dispose()
            .then((_) async {
              if (_lastProjection != null) {
                await _lastProjection;
              }
              await syncService?.disconnectNote();
            })
        );
      });
```

**Verify**: `dart analyze lib/features/notes/presentation/controllers/note_editor_provider.dart` → exit 0, no errors.

## Test plan

- Run existing Yjs domain tests.
- Verification: `flutter test test/features/notes/domain/` → all pass.

## Done criteria

- [ ] `dart analyze` exits 0 for all modified files.
- [ ] Fallback mechanism is in place for `content_fixed/$id`.
- [ ] `_lastProjection` is awaited during disposal in the provider.
- [ ] No files outside the in-scope list are modified.
- [ ] `plans/README.md` status row updated.

## STOP conditions

Stop and report back if:
- The code at the locations in "Current state" doesn't match the excerpts.
- A step's verification fails twice after a reasonable fix attempt.

## Maintenance notes
- Once all users migrate and corrupt nodes are overwritten with `content_fixed`, we can potentially drop `content` in a future major version, though keeping it is harmless for backwards compatibility.
