# Yjs Synchronization Engine Audit & Implementation Plan

## Goal Description
Conduct a comprehensive review of the `Yjs` synchronization engine between Flutter (`super_editor`, SQLite, `yjs_dart`) and the Go backend to identify and resolve systemic issues preventing note edits from being saved.

The user reported that even after the `getText` fix, edits made to notes on Android are still not being saved when the user exits the note.

## Root Cause Analysis (Hypotheses)

1. **Persistent Corruption of Root Types**:
   Due to the previous bug in `yjs_dart`, many existing `content/$id` root types were incorrectly initialized as `YMap` in the user's database. When the user edits these existing paragraphs, our new code (`_doc.getText('content/$id')`) throws a `TypeMismatch` exception. The exception is caught and the text update is silently discarded. Because Yjs root types cannot be deleted or changed once created, these specific paragraphs are permanently corrupted.
   *Proof*: The `catch (e)` in `_serializeNode` logs a `corrupted type` error, resulting in no text being written to the CRDT.

2. **Asynchronous Disposal Race Condition**:
   In `NoteEditorController.dispose()`, we call `await _coordinator?.dispose();`. This calls `flushNow()`, which triggers `yjsMgr.projectNodes` via an unawaited callback. Immediately after, `syncService.disconnectNote()` is called, which persists the `YDoc` and closes the WebSocket. If the app is closed or the isolate is paused before `projectNodes` (a Drift transaction) completes, the SQLite view might not update, though the CRDT blob is saved.
   
3. **super_editor Delta Mapping Missing**:
   Currently, we are entirely replacing the `YText` content (`sharedType.delete(0, len); sharedType.insert(0, newText);`) instead of applying specific deltas. While inefficient, this should not cause data loss unless `currentText.length` is misaligned due to concurrent edits.

## Proposed Changes

### 1. Graceful Recovery for Corrupted Nodes (Fallback Key)
Since we cannot change a root type in Yjs from `YMap` to `YText`, we must introduce a fallback mechanism for corrupted nodes.
#### [MODIFY] lib/features/notes/domain/yjs_doc_editor_bridge.dart
- Update `_serializeNode` to catch the type mismatch exception. If caught, fallback to a new root type key: `content_fixed/$id`.
- Write the text to `content_fixed/$id` instead.

#### [MODIFY] lib/features/notes/domain/yjs_node_codec.dart
- Update `_readNodeFromYMap` and `_readNodeFromJsonString` to first attempt to read from `content_fixed/$id` (as a `YText`). If it doesn't exist, try `content/$id`.

### 2. Await `projectNodes` on Dispose
Ensure that local SQLite projections are fully awaited before the WebSocket is disconnected and the provider is disposed, guaranteeing no background tasks are killed prematurely.
#### [MODIFY] lib/features/notes/presentation/controllers/note_editor_provider.dart
- Change the `onDocChanged` callback to return a `Future<void>`.
- Refactor `dispose()` chains to ensure `projectNodes` completes if it's currently running.

### 3. Comprehensive Logging for Diagnostics
- Add strict, visible logging (e.g. `debugPrint`) during the serialization fallback so we can confirm if corruption was the true cause of the user's ongoing issue.

## User Review Required
Please review this plan. The most likely reason the app is still failing for you is that the previous bug permanently corrupted the paragraphs you are trying to edit, turning their text containers into dictionaries in the database. Since Yjs doesn't allow changing a container's type once created, we need to implement a "fallback" container (`content_fixed/$id`) to bypass the corrupted ones.

## Open Questions
- Did you try creating a **brand new note** and typing into it, or did you only test by editing existing notes? If a brand new note works but old ones fail, it 100% confirms the corruption hypothesis.
- Are you comfortable with me implementing this fallback mechanism to salvage the existing notes?
