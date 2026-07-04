# Plan 045: Editor Simplification and Bugfixes

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 5d1713f..HEAD -- lib/features/notes/presentation/widgets/custom_task_component.dart lib/features/notes/presentation/widgets/note_editor.dart lib/features/notes/presentation/note_editor_screen.dart lib/features/notes/presentation/controllers/note_editor_controller.dart lib/features/notes/domain/node_sync_manager.dart`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: MED
- **Depends on**: none
- **Category**: bug | simplification | tech-debt
- **Planned at**: commit `5d1713f`, 2026-07-04

## Design decisions

These decisions were validated with the user before writing this plan:

1. **DB is the source of truth for task completion state.** The checkbox reacts to stream updates from the database, not optimistic editor commands. The user accepts ~100-200ms latency on the checkbox response.
2. **Recurring tasks**: checkbox checks, snackbar shows "Próx. em: \<date\>", then after ~1s the checkbox unchecks (since the DB keeps the task `open` with the next due date). This animation uses local widget state (`_completingTaskIds`), NOT editor document commands.
3. **No optimistic updates, no rollback code.** If `completeTask` fails, the state simply doesn't change.

## Why this matters

1. **Business logic in the wrong place**: `CustomTaskComponentBuilder.createViewModel` currently contains recurrence logic, optimistic editor commands, error rollback, and a `Future.delayed(400ms)`. A component builder should only build components.
2. **Feedback loop**: Optimistic `ChangeTaskCompletionRequest` in `setComplete` triggers `NodeSyncManager`, which writes to SQLite, which emits a stream, which triggers `updateNodesIncrementally` — unnecessary write cycle.
3. **Flickering**: The 400ms delay for recurring tasks races with the DB stream, causing visual reversion.
4. **Double `.when` nesting**: `NoteEditorScreen` nests two `AsyncValue.when` blocks unnecessarily.
5. **Redundant watcher**: `ref.watch(noteEditorControllerProvider)` in `NoteEditor.build` serves no purpose.

---

## Current state

### `CustomTaskComponentBuilder.createViewModel` (the core problem)
**File**: [`custom_task_component.dart:55-91`](file:///c:/Users/rigleyc/projects/supanotes/lib/features/notes/presentation/widgets/custom_task_component.dart#L55-L91)
```dart
setComplete: (bool isComplete) async {
  if (isComplete && hideCompleted) {
    _animatingNodeIds.add(node.id);
    FocusManager.instance.primaryFocus?.unfocus();
    composer?.clearSelection();
  }
  _editor.execute([                          // ← optimistic update (REMOVE)
    ChangeTaskCompletionRequest(nodeId: node.id, isComplete: isComplete),
  ]);
  try {
    if (isComplete) {
      await onTaskComplete?.call(node.id);
      final taskMeta = taskMetadataById[node.id];
      if (taskMeta?.recurrence != null) {    // ← recurrence logic here (WRONG PLACE)
        Future.delayed(const Duration(milliseconds: 400), () { ... });
      }
    } else {
      await onTaskReopen?.call(node.id);
    }
  } catch (e) {                              // ← rollback (REMOVE)
    _editor.execute([
      ChangeTaskCompletionRequest(nodeId: node.id, isComplete: !isComplete),
    ]);
    onError?.call(e);
  }
},
```

### `_CustomTaskComponentState` local `_isComplete`
**File**: [`custom_task_component.dart:286-288`](file:///c:/Users/rigleyc/projects/supanotes/lib/features/notes/presentation/widgets/custom_task_component.dart#L286-L288)
```dart
onChanged: (val) {
  setState(() => _isComplete = val);          // ← local optimistic toggle
  widget.viewModel.setComplete?.call(val);
},
```

### Double `.when` nesting in `NoteEditorScreen`
**File**: [`note_editor_screen.dart:51-58`](file:///c:/Users/rigleyc/projects/supanotes/lib/features/notes/presentation/note_editor_screen.dart#L51-L58)

### Task completion update in `NoteEditor.didUpdateWidget` (Path A)
**File**: [`note_editor.dart:151-175`](file:///c:/Users/rigleyc/projects/supanotes/lib/features/notes/presentation/widgets/note_editor.dart#L151-L175)

This path **already works correctly** as the reactive mechanism: when `taskMetadata` changes from the stream, it compares `node.isComplete` vs `taskMetadata[id].isCompleted` and issues `ChangeTaskCompletionRequest` to sync the editor document. This is the path we'll rely on instead of optimistic updates.

---

## Commands you will need

| Purpose   | Command                  | Expected on success |
|-----------|--------------------------|---------------------|
| Run tests | `flutter test`           | All passing         |

---

## Scope

**In scope**:
- `lib/features/notes/presentation/widgets/custom_task_component.dart`
- `lib/features/notes/presentation/widgets/note_editor.dart`
- `lib/features/notes/presentation/note_editor_screen.dart`
- `lib/features/notes/presentation/controllers/notes_providers.dart`
- `lib/features/notes/presentation/controllers/note_editor_controller.dart`
- `lib/features/notes/domain/node_sync_manager.dart`

**Out of scope**:
- Database tables, DAO logic, or repository layer.
- `TaskSnackBarHelper` (stays as-is — it just shows a snackbar).
- `NoteEditorDelegate` (stays as-is — its signature is fine).

---

## Steps

### Step 1: Simplify `setComplete` in `CustomTaskComponentBuilder`

Remove all business logic from the `setComplete` callback. It should only call the delegate and manage local animation state for recurring tasks.

**File**: `lib/features/notes/presentation/widgets/custom_task_component.dart`

**Change the `onTaskComplete` callback type** from `Future<void>` to `Future<DateTime?>` (matching `TaskSnackBarHelper.completeTaskWithFeedback`'s return type):
```dart
// Before
final Future<void> Function(String taskId)? onTaskComplete;

// After
final Future<DateTime?> Function(String taskId)? onTaskComplete;
```

**Add a `_completingTaskIds` set** alongside the existing `_animatingNodeIds`:
```dart
final Set<String> _completingTaskIds = {};
```

**Rewrite `setComplete`**:
```dart
setComplete: (bool isComplete) async {
  if (isComplete) {
    // Mark as visually completing (local state for instant feedback)
    _completingTaskIds.add(node.id);
    requestRebuild?.call();

    if (hideCompleted) {
      _animatingNodeIds.add(node.id);
      FocusManager.instance.primaryFocus?.unfocus();
      composer?.clearSelection();
    }

    try {
      final nextDue = await onTaskComplete?.call(node.id);

      if (nextDue != null) {
        // Recurring: keep visual check for ~1s, then let stream uncheck
        await Future.delayed(const Duration(seconds: 1));
      }
    } finally {
      _completingTaskIds.remove(node.id);
      requestRebuild?.call();
    }
    // Stream from DB will update the document via didUpdateWidget Path A.
  } else {
    await onTaskReopen?.call(node.id);
    // Stream from DB will update the document via didUpdateWidget Path A.
  }
},
```

**Update `createViewModel` to use `_completingTaskIds` for the visual state**:
```dart
isComplete: _completingTaskIds.contains(node.id) || node.isComplete,
```

**What was removed**:
- `_editor.execute([ChangeTaskCompletionRequest(...)])` — no more optimistic document edits
- `Future.delayed(400ms)` recurrence hack — replaced by clean 1s delay with local state
- `catch (e) { _editor.execute(rollback) }` — no rollback needed
- `onError` callback — can be removed from constructor too

**Verify**: App builds. Tapping a checkbox calls the repo and the stream updates the document.

---

### Step 2: Remove local `_isComplete` state from `_CustomTaskComponentState`

The local `_isComplete` was needed for optimistic UI. Now the checkbox reads from `viewModel.isComplete` (which includes the `_completingTaskIds` override from Step 1).

**File**: `lib/features/notes/presentation/widgets/custom_task_component.dart`

**Remove** the `_isComplete` field and its `initState`/`didUpdateWidget` assignments:
```dart
// REMOVE:
late bool _isComplete;

// REMOVE from initState:
_isComplete = widget.viewModel.isComplete;

// REMOVE from didUpdateWidget:
if (widget.viewModel.isComplete != oldWidget.viewModel.isComplete) {
  _isComplete = widget.viewModel.isComplete;
}
```

**Update the checkbox to read from viewModel directly**:
```dart
// Before
_TaskCheckboxHitTarget(
  value: _isComplete,
  onChanged: (val) {
    setState(() => _isComplete = val);
    widget.viewModel.setComplete?.call(val);
  },

// After
_TaskCheckboxHitTarget(
  value: widget.viewModel.isComplete,
  onChanged: (val) {
    widget.viewModel.setComplete?.call(val);
  },
```

**Verify**: Checkbox visual state is driven by `viewModel.isComplete`. No local state duplication.

---

### Step 3: Sync suspension in `NodeSyncManager`

Wrap `updateNodesIncrementally` in a sync suspension so that programmatic document edits (from stream → didUpdateWidget) don't trigger unnecessary SQLite writes.

**File**: `lib/features/notes/domain/node_sync_manager.dart` — add:
```dart
void suspendSync() {
  _document.removeListener(_onDocumentChanged);
}

void resumeSync() {
  _document.addListener(_onDocumentChanged);
}
```

**File**: `lib/features/notes/presentation/controllers/note_editor_controller.dart` — wrap `updateNodesIncrementally`:
```dart
void updateNodesIncrementally(List<NoteNode> incomingNodes) {
  final doc = document;
  final ed = editor;
  if (doc == null || ed == null) return;

  _nodeSyncManager?.suspendSync();
  try {
    // ... existing diff logic unchanged ...
  } finally {
    _nodeSyncManager?.resumeSync();
  }
}
```

Also expose `suspendSync`/`resumeSync` on the controller for the didUpdateWidget task-sync path in `NoteEditor`.

**Verify**: Typing in the editor doesn't cause recursive DB writes. The stream → editor path doesn't echo writes back.

---

### Step 4: Guard `didUpdateWidget` Path A with sync suspension

When `NoteEditor.didUpdateWidget` syncs task completion state from the tasks table into the document (Path A), those editor commands shouldn't trigger `NodeSyncManager` writes — the data already came FROM the DB.

**File**: `lib/features/notes/presentation/widgets/note_editor.dart`

Wrap the task-sync loop in `didUpdateWidget` with sync suspension:
```dart
if (widget.taskMetadata != oldWidget.taskMetadata &&
    _controller?.editor != null &&
    _controller?.document != null) {
  _controller?.suspendSync();  // ← ADD
  try {
    final doc = _controller!.document!;
    final requests = <EditRequest>[];
    for (final node in doc) {
      if (node is TaskNode) {
        final isDbCompleted = widget.taskMetadata[node.id]?.isCompleted ?? false;
        if (node.isComplete != isDbCompleted) {
          requests.add(ChangeTaskCompletionRequest(
            nodeId: node.id,
            isComplete: isDbCompleted,
          ));
        }
      }
    }
    if (requests.isNotEmpty) {
      _controller!.editor!.execute(requests);
    }
  } finally {
    _controller?.resumeSync();  // ← ADD
  }
}
```

**Verify**: Completing a task via the checkbox → repo write → tasks stream → didUpdateWidget Path A → document update, WITHOUT triggering a NodeSyncManager echo write.

---

### Step 5: Compose providers to eliminate double `.when`

**File**: `lib/features/notes/presentation/controllers/notes_providers.dart` — add:
```dart
final combinedNoteEditorStateProvider = Provider.autoDispose
    .family<AsyncValue<(List<NoteNode>, NoteWithTasks)>, String>((ref, noteId) {
  final nodes = ref.watch(noteNodesProvider(noteId));
  final noteWithTasks = ref.watch(noteWithTasksProvider(noteId));

  if (nodes.hasError) return AsyncValue.error(nodes.error!, nodes.stackTrace!);
  if (noteWithTasks.hasError) return AsyncValue.error(noteWithTasks.error!, noteWithTasks.stackTrace!);

  if (nodes.isLoading || noteWithTasks.isLoading) {
    return const AsyncValue.loading();
  }

  return AsyncValue.data((nodes.requireValue, noteWithTasks.requireValue));
});
```

**File**: `lib/features/notes/presentation/note_editor_screen.dart` — replace double `.when` with single:
```dart
final combinedAsync = ref.watch(combinedNoteEditorStateProvider(widget.noteId));

return combinedAsync.when(
  data: (data) {
    final (nodes, noteWithTasks) = data;
    // ... rest of build
  },
  loading: () => ...,
  error: (e, st) => ...,
);
```

**Verify**: Single loading spinner, single error state, no nesting.

---

### Step 6: Remove redundant `ref.watch` in `NoteEditor.build`

**File**: `lib/features/notes/presentation/widgets/note_editor.dart`

Remove:
```dart
final controller = ref.watch(noteEditorControllerProvider(widget.noteId));
_controller = controller;
```

The `_controller` is already set in `initState` and updated in `didUpdateWidget`.

**Verify**: Editor works correctly without the redundant watch.

---

### Step 7: Update `onTaskComplete` type in `NoteEditorDelegate` and wiring

**File**: `lib/features/notes/presentation/controllers/note_editor_delegate.dart`

Change the callback type:
```dart
// Before
final Future<void> Function(String taskId)? onTaskComplete;

// After
final Future<DateTime?> Function(String taskId)? onTaskComplete;
```

**Files**: `note_editor_screen.dart`, `inbox_screen.dart` — the `TaskSnackBarHelper.completeTaskWithFeedback` already returns `Future<DateTime?>`, so the wiring should work without changes. Verify both screens compile.

Also update `NoteEditor` and `CustomTaskComponentBuilder` constructor to use the new type.

**Verify**: Both `NoteEditorScreen` and `InboxScreen` build correctly.

---

### Step 8: Clean up `onError` parameter

Since there's no more rollback logic, the `onError` callback in `CustomTaskComponentBuilder` is unused.

**File**: `lib/features/notes/presentation/widgets/custom_task_component.dart` — remove:
- `onError` constructor parameter
- All references to `onError`

**File**: `lib/features/notes/presentation/widgets/note_editor.dart` — remove `onError` from builder construction.

**Verify**: No unused parameter warnings.

---

## Test plan

```bash
flutter test test/features/notes/presentation/note_editor_screen_test.dart
flutter test
```

## Done criteria

- [ ] `setComplete` has zero editor commands — only calls repo via delegate.
- [ ] Recurring task visual animation uses `_completingTaskIds` (local state), not document manipulation.
- [ ] No `Future.delayed(400ms)` hack.
- [ ] No rollback code in the component builder.
- [ ] Sync is suspended during `updateNodesIncrementally` and `didUpdateWidget` Path A.
- [ ] Single `.when` in `NoteEditorScreen` via composed provider.
- [ ] Redundant `ref.watch` removed from `NoteEditor.build`.
- [ ] `onError` parameter removed from builder.

## STOP conditions

- If removing optimistic updates causes the checkbox to not respond at all (stream not arriving).
- If sync suspension causes editor text changes to stop persisting.
- If `_completingTaskIds` visual override doesn't render correctly in the component.
- If the `onTaskComplete` type change causes cascading breaks beyond the in-scope files.
