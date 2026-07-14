# Plan 061: Fix Task Sync Data Loss & Metadata Propagation

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 2be0c77..HEAD -- lib/features/notes/presentation/controllers/note_editor_provider.dart lib/features/tasks/presentation/widgets/task_metadata_sheet.dart lib/features/notes/domain/yjs_doc_editor_bridge.dart lib/features/notes/presentation/controllers/note_editor_controller.dart`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P0
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: bug (data loss)
- **Planned at**: commit `2be0c77`, 2026-07-14

## Why this matters

Currently, when a user completes a task and quickly backs out of the note, the WebSocket is disconnected *before* the local CRDT flush finishes, meaning the completion state is silently dropped and permanently lost since it was never persisted to the local SQLite CRDT store. Additionally, when editing a task's Due Date or Recurrence, the edits bypass the YDoc entirely, causing the backend to wipe them out on the next sync. This plan fixes both data-loss vectors, cementing the YDoc as the single source of truth for task metadata as specified in Phase 4 of `058-yjs-architecture-completion`.

## Current state

- `lib/features/notes/presentation/controllers/note_editor_provider.dart` — Manages the lifecycle of the editor and sync connection. Currently disconnects the WS *before* flushing the controller:
  ```dart
        ref.onDispose(() {
          disposed = true;
          syncService?.disconnectNote(); // WS closed too early!
          controller.dispose(); // flushNow() runs here and fails to send
        });
  ```
- `lib/features/notes/domain/yjs_doc_editor_bridge.dart` — Bridges Editor state to YDoc. Missing a public method to update metadata.
- `lib/features/tasks/presentation/widgets/task_metadata_sheet.dart` — Updates task metadata via SQLite only, bypassing YDoc:
  ```dart
      await ref.read(taskControllerProvider.notifier).updateTaskMetadata(
            widget.task.id,
            dueDate: _dueDate,
            clearDueDate: _dueDate == null,
            recurrence: _recurrence,
            clearRecurrence: _recurrence == null,
          );
      if (mounted) Navigator.pop(context);
  ```

## Commands you will need

| Purpose   | Command                  | Expected on success |
|-----------|--------------------------|---------------------|
| Analyze   | `flutter analyze`        | exit 0, no errors   |
| Test      | `flutter test`           | all pass            |

## Scope

**In scope**:
- `lib/features/notes/presentation/controllers/note_editor_provider.dart`
- `lib/features/notes/domain/yjs_doc_editor_bridge.dart`
- `lib/features/notes/presentation/controllers/note_editor_controller.dart`
- `lib/features/tasks/presentation/widgets/task_metadata_sheet.dart`

**Out of scope**:
- `lib/core/sync/sync_service.dart` (do not modify the sync core engine)
- Any backend Go code

## Git workflow

- Branch: `fix/059-task-sync-data-loss`
- Commit per step; message style: `fix(notes): preserve CRDT task metadata`

## Steps

### Step 1: Fix Disposal Order & Persist Local Edits

In `lib/features/notes/presentation/controllers/note_editor_provider.dart`:
1. Modify `ref.onDispose` to wait for `controller.dispose()` *before* disconnecting the note. Note: `controller.dispose()` returns a `Future<void>`, so you must execute it, but `onDispose` is synchronous. However, we can simply invert the calls. Better yet, since it's auto-dispose, let's call `yjsMgr.persist(noteId)` inside `onDocChanged`.
2. In `onDocChanged: () => yjsMgr.projectNodes(noteId)`, change it to a block that also calls `yjsMgr.persist(noteId)`. This guarantees that *every* local keystroke/edit is saved to SQLite immediately, surviving offline closures.

**Target Shape**:
```dart
            onDocChanged: () {
              yjsMgr.projectNodes(noteId);
              yjsMgr.persist(noteId);
            },
```
And swap the dispose lines:
```dart
      ref.onDispose(() {
        disposed = true;
        controller.dispose();
        syncService?.disconnectNote();
      });
```

**Verify**: `flutter analyze` -> no errors.

### Step 2: Add `updateTaskMetadata` to Yjs Bridge

In `lib/features/notes/domain/yjs_doc_editor_bridge.dart`:
Add a public method that updates `YMap("tasks")`:

```dart
  void updateTaskMetadata(
    String nodeId, {
    DateTime? dueDate,
    String? recurrence,
    bool clearDueDate = false,
    bool clearRecurrence = false,
  }) {
    _doc.transact((txn) {
      final tasksMap = _doc.getMap('tasks');
      final existingRaw = tasksMap.getAttr(nodeId);
      if (existingRaw == null) return;
      
      try {
        final entry = jsonDecode(existingRaw as String) as Map<String, dynamic>;
        
        if (clearDueDate) {
          entry.remove('dueDate');
        } else if (dueDate != null) {
          entry['dueDate'] = _formatDueDate(dueDate);
        }

        if (clearRecurrence) {
          entry.remove('recurrence');
        } else if (recurrence != null) {
          entry['recurrence'] = recurrence;
        }

        tasksMap.setAttr(nodeId, jsonEncode(entry));
      } catch (e) {
        debugPrint('[YjsDocEditorBridge] Error updating task metadata: $e');
      }
    });

    final update = encodeStateAsUpdate(_doc);
    _sendUpdate(update);
  }
```

In `lib/features/notes/presentation/controllers/note_editor_controller.dart`:
Expose this method by delegating to `_bridge`:
```dart
  void updateTaskMetadata(
    String nodeId, {
    DateTime? dueDate,
    String? recurrence,
    bool clearDueDate = false,
    bool clearRecurrence = false,
  }) {
    _bridge?.updateTaskMetadata(
      nodeId,
      dueDate: dueDate,
      recurrence: recurrence,
      clearDueDate: clearDueDate,
      clearRecurrence: clearRecurrence,
    );
  }
```

**Verify**: `flutter analyze` -> no errors.

### Step 3: Wire UI to YDoc Controller

In `lib/features/tasks/presentation/widgets/task_metadata_sheet.dart`:
Inside `_save()`, right after calling `taskControllerProvider.notifier.updateTaskMetadata`, also retrieve the `noteEditorControllerProvider` and update the YDoc.

**Target Shape**:
```dart
    final noteId = widget.noteId;
    final taskId = widget.task.id;
    
    // SQLite update
    await ref.read(taskControllerProvider.notifier).updateTaskMetadata(
          taskId,
          dueDate: _dueDate,
          clearDueDate: _dueDate == null,
          recurrence: _recurrence,
          clearRecurrence: _recurrence == null,
        );

    // CRDT update
    ref.read(noteEditorControllerProvider(noteId)).updateTaskMetadata(
      taskId,
      dueDate: _dueDate,
      clearDueDate: _dueDate == null,
      recurrence: _recurrence?.value,
      clearRecurrence: _recurrence == null,
    );
```
*(Note: TaskRecurrence enum has a `.value` property. Use it to extract the string value. Match the exact type used by `TaskController.updateTaskMetadata`)*.

**Verify**: `flutter test` -> all pass.

## Done criteria

- [ ] `flutter analyze` exits 0
- [ ] `flutter test` exits 0
- [ ] `controller.dispose()` occurs *before* `syncService?.disconnectNote()` in `note_editor_provider.dart`
- [ ] `TaskMetadataSheet` calls `updateTaskMetadata` on the `NoteEditorController`
- [ ] `plans/README.md` status row updated

## STOP conditions

- If `yjsMgr.persist(noteId)` does not exist in `YjsSyncManager`.
- If `TaskMetadataSheet` does not have access to `widget.noteId` in its current state.

## Maintenance notes

- Future developers: Remember that SQLite `tasks` table is merely a projection of the `YDoc`. Any manual updates to SQLite that do not go through `YjsDocEditorBridge` will be silently overwritten and lost on the next sync.
