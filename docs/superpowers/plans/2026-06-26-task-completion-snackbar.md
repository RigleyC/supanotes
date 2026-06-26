# Task Completion Snackbar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a snackbar notification when a task is completed, showing "Tarefa concluída! Próx. ocorrência: [Date]" with an "Undo" button.

**Architecture:** Modify the `completeTask` method chain to return the next due date, then use it in a new `AppMessenger.showTaskCompleted` method to display the snackbar.

**Tech Stack:** Flutter, Dart, Drift (local database), Riverpod

---

## File Structure

| File | Responsibility |
|------|----------------|
| `lib/core/database/daos/tasks_dao.dart` | Return `DateTime?` from `completeTask` |
| `lib/features/tasks/data/local/tasks_local_repository.dart` | Propagate return type |
| `lib/features/tasks/data/tasks_repository.dart` | Update interface and implementation |
| `lib/shared/widgets/app_snackbar.dart` | Add `showTaskCompleted` method |
| `lib/features/notes/presentation/controllers/note_editor_delegate.dart` | Add `onTaskCompleteWithDate` callback |
| `lib/features/notes/presentation/widgets/custom_task_component.dart` | Use new callback |
| `lib/features/notes/presentation/inbox_screen.dart` | Implement callback |
| `lib/features/notes/presentation/note_editor_screen.dart` | Implement callback |

---

### Task 1: Update TasksDao.completeTask Return Type

**Files:**
- Modify: `lib/core/database/daos/tasks_dao.dart:115-163`

- [ ] **Step 1: Modify completeTask to return DateTime?**

```dart
/// Marks the row with [id] as completed, records the completion event
/// in the [LocalTaskCompletions] history, and — if the task is
/// recurring — schedules the next occurrence.
///
/// Returns the next due date for recurring tasks, or null for
/// non-recurring tasks.
Future<DateTime?> completeTask(String id) async {
  final task = await (select(tasks)..where((t) => t.id.equals(id)))
      .getSingleOrNull();
  if (task == null) return null;

  final now = DateTime.now();
  DateTime? nextDue;

  await transaction(() async {
    // 1. Record the completion event.
    if (completionsDao != null) {
      await completionsDao!.recordCompletion(
        taskId: task.id,
        userId: task.userId,
        completedAt: now,
      );
    }

    // 2. If recurring, schedule the next occurrence on the same row.
    final recurrence = task.recurrence;
    if (recurrence != null) {
      nextDue = _nextDueDate(
        from: task.dueDate ?? now,
        recurrence: recurrence,
      );
      if (nextDue != null) {
        await (update(tasks)..where((t) => t.id.equals(id))).write(
          TasksCompanion(
            dueDate: Value(nextDue),
            completedAt: const Value(null),
            status: const Value('open'),
            updatedAt: Value(now),
            isDirty: const Value(true),
          ),
        );
        return;
      }
    }

    // 3. Non-recurring or unsupported recurrence: mark completed.
    await (update(tasks)..where((t) => t.id.equals(id))).write(
      TasksCompanion(
        status: const Value('done'),
        completedAt: Value(now),
        updatedAt: Value(now),
        isDirty: const Value(true),
      ),
    );
  });

  return nextDue;
}
```

- [ ] **Step 2: Verify no compilation errors**

Run: `cd lib && dart analyze core/database/daos/tasks_dao.dart`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add lib/core/database/daos/tasks_dao.dart
git commit -m "feat(tasks): return next due date from completeTask"
```

---

### Task 2: Update TasksLocalRepository.completeTask

**Files:**
- Modify: `lib/features/tasks/data/local/tasks_local_repository.dart:73-75`

- [ ] **Step 1: Update method signature and return type**

```dart
Future<DateTime?> completeTask(String id) async {
  return await _dao.completeTask(id);
}
```

- [ ] **Step 2: Verify no compilation errors**

Run: `cd lib && dart analyze features/tasks/data/local/tasks_local_repository.dart`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add lib/features/tasks/data/local/tasks_local_repository.dart
git commit -m "feat(tasks): propagate DateTime? return from local repo"
```

---

### Task 3: Update TasksRepository Interface and Implementation

**Files:**
- Modify: `lib/features/tasks/data/tasks_repository.dart:26`
- Modify: `lib/features/tasks/data/tasks_repository.dart:139`

- [ ] **Step 1: Update interface method signature**

```dart
abstract class ITasksRepository {
  String get userId;
  Stream<List<TaskModel>> watchTodayTasks();
  Stream<List<TaskModel>> watchOverdueTasks();
  Stream<List<TaskModel>> watchTodayDueTasks();
  Stream<List<TaskModel>> watchUndatedOpenTasks();
  Stream<List<TaskModel>> watchByNote(String noteId);
  Future<TaskModel> createTask({required String noteId, required String title, DateTime? dueDate, TaskRecurrence? recurrence, int position = 0});
  Future<DateTime?> completeTask(String id);
  Future<void> reopenTask(String id);
  Future<void> updateTask(String id, {String? title, DateTime? dueDate, TaskRecurrence? recurrence, int? position, bool clearDueDate = false, bool clearRecurrence = false});
  Future<void> deleteTask(String id);
  Future<void> reorderTasks(String noteId, List<String> orderedIds);
}
```

- [ ] **Step 2: Update implementation method**

```dart
@override
Future<DateTime?> completeTask(String id) => _local.completeTask(id);
```

- [ ] **Step 3: Verify no compilation errors**

Run: `cd lib && dart analyze features/tasks/data/tasks_repository.dart`
Expected: No errors

- [ ] **Step 4: Commit**

```bash
git add lib/features/tasks/data/tasks_repository.dart
git commit -m "feat(tasks): update repository interface for DateTime? return"
```

---

### Task 4: Add showTaskCompleted to AppMessenger

**Files:**
- Modify: `lib/shared/widgets/app_snackbar.dart`

- [ ] **Step 1: Add showTaskCompleted method**

```dart
import 'package:flutter/material.dart';

class AppMessenger {
  AppMessenger._();

  static void showSuccess(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
      ));
  }

  static void showError(
    BuildContext context,
    String message, {
    VoidCallback? onRetry,
  }) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
        behavior: SnackBarBehavior.floating,
        action: onRetry != null
            ? SnackBarAction(
                label: 'Tentar novamente',
                onPressed: onRetry,
              )
            : null,
      ));
  }

  static void showInfo(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ));
  }

  static void showTaskCompleted(
    BuildContext context, {
    required DateTime? nextDueDate,
    required VoidCallback onUndo,
  }) {
    final message = nextDueDate != null
        ? 'Tarefa concluída! Próx. ocorrência: ${_formatDate(nextDueDate)}'
        : 'Tarefa concluída!';

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Desfazer',
          textColor: Colors.white,
          onPressed: onUndo,
        ),
      ));
  }

  static String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}
```

- [ ] **Step 2: Verify no compilation errors**

Run: `cd lib && dart analyze shared/widgets/app_snackbar.dart`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add lib/shared/widgets/app_snackbar.dart
git commit -m "feat(ui): add showTaskCompleted snackbar method"
```

---

### Task 5: Update NoteEditorDelegate

**Files:**
- Modify: `lib/features/notes/presentation/controllers/note_editor_delegate.dart`

- [ ] **Step 1: Add onTaskCompleteWithDate callback**

```dart
import 'package:supanotes/features/notes/domain/task_entry.dart';
import 'package:supanotes/features/tasks/domain/task_model.dart';

class NoteEditorDelegate {
  final Future<void> Function(String noteId, String markdown, List<TaskEntry> tasks) snapshotSave;
  final Future<void> Function(String noteId)? emptyNoteExit;
  final void Function(bool hasContent)? onHasContentChanged;
  final void Function(TaskModel? task, Future<void> Function() flushSnapshot)? onTaskLongPress;
  final Future<void> Function(String taskId)? onTaskComplete;
  final Future<void> Function(String taskId)? onTaskReopen;
  final Future<DateTime?> Function(String taskId)? onTaskCompleteWithDate;
  final Future<void> Function(String id, String noteId, String filePath, String mimeType)? onUploadFile;

  const NoteEditorDelegate({
    required this.snapshotSave,
    this.emptyNoteExit,
    this.onHasContentChanged,
    this.onTaskLongPress,
    this.onTaskComplete,
    this.onTaskReopen,
    this.onTaskCompleteWithDate,
    this.onUploadFile,
  });
}
```

- [ ] **Step 2: Verify no compilation errors**

Run: `cd lib && dart analyze features/notes/presentation/controllers/note_editor_delegate.dart`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add lib/features/notes/presentation/controllers/note_editor_delegate.dart
git commit -m "feat(notes): add onTaskCompleteWithDate callback to delegate"
```

---

### Task 6: Update CustomTaskComponentBuilder

**Files:**
- Modify: `lib/features/notes/presentation/widgets/custom_task_component.dart:17-97`

- [ ] **Step 1: Add onTaskCompleteWithDate parameter and use it**

```dart
class CustomTaskComponentBuilder implements ComponentBuilder {
  CustomTaskComponentBuilder(
    this._editor, {
    this.taskMetadataById = const {},
    this.hideCompleted = false,
    this.onTaskLongPress,
    this.onTaskComplete,
    this.onTaskReopen,
    this.onTaskCompleteWithDate,
    this.requestRebuild,
  });

  final Editor _editor;
  Map<String, TaskModel> taskMetadataById;
  bool hideCompleted;
  ValueChanged<String>? onTaskLongPress;
  final Future<void> Function(String taskId)? onTaskComplete;
  final Future<void> Function(String taskId)? onTaskReopen;
  final Future<DateTime?> Function(String taskId)? onTaskCompleteWithDate;
  final VoidCallback? requestRebuild;
  final Set<String> _pendingResetNodeIds = {};
  final Set<String> _animatingNodeIds = {};

  @override
  TaskComponentViewModel? createViewModel(
    Document document,
    DocumentNode node,
  ) {
    if (node is! TaskNode) return null;

    final metadata = taskMetadataById[node.id];

    return CustomTaskComponentViewModel(
      nodeId: node.id,
      createdAt: node.metadata[NodeMetadata.createdAt],
      padding: EdgeInsets.zero,
      indent: node.indent,
      isComplete: node.isComplete,
      setComplete: (bool isComplete) async {
        if (isComplete && hideCompleted) {
          _animatingNodeIds.add(node.id);
          FocusManager.instance.primaryFocus?.unfocus();
        }
        _editor.execute([
          ChangeTaskCompletionRequest(nodeId: node.id, isComplete: isComplete),
        ]);

        if (isComplete) {
          if (onTaskCompleteWithDate != null) {
            await onTaskCompleteWithDate!.call(node.id);
          } else {
            await onTaskComplete?.call(node.id);
          }
        } else {
          await onTaskReopen?.call(node.id);
        }

        final taskMeta = taskMetadataById[node.id];
        if (isComplete && taskMeta?.recurrence != null) {
          _pendingResetNodeIds.add(node.id);
          Future.delayed(_recurrenceResetDelay, () {
            if (!_pendingResetNodeIds.remove(node.id)) return;
            final exists = document.getNodeById(node.id) != null;
            if (exists) {
              try {
                _editor.execute([
                  ChangeTaskCompletionRequest(nodeId: node.id, isComplete: false),
                ]);
              } catch (_) {
                // Editor was disposed while the timer was pending — safe to ignore.
              }
            }
          });
        } else if (!isComplete) {
          // User reopened the task — cancel any pending reset
          _pendingResetNodeIds.remove(node.id);
        }
      },
      text: node.text,
      textDirection: getParagraphDirection(node.text.toPlainText()),
      textAlignment: TextAlign.left,
      textStyleBuilder: noStyleBuilder,
      selectionColor: const Color(0x00000000),
      dueDate: metadata?.dueDate,
      recurrence: metadata?.recurrence,
    );
  }
```

- [ ] **Step 2: Update NoteEditor to pass onTaskCompleteWithDate**

```dart
// In lib/features/notes/presentation/widgets/note_editor.dart
_taskComponentBuilder = CustomTaskComponentBuilder(
  _controller!.editor!,
  taskMetadataById: widget.taskMetadata,
  hideCompleted: widget.hideCompleted,
  onTaskLongPress: widget.isReadOnly
      ? null
      : (taskId) => widget.delegate.onTaskLongPress?.call(
          widget.taskMetadata[taskId],
          () => _controller!.persistSnapshotNow(),
        ),
  onTaskComplete: widget.delegate.onTaskComplete,
  onTaskReopen: widget.delegate.onTaskReopen,
  onTaskCompleteWithDate: widget.delegate.onTaskCompleteWithDate,
  requestRebuild: () {
    if (mounted) setState(() {});
  },
);
```

- [ ] **Step 3: Verify no compilation errors**

Run: `cd lib && dart analyze features/notes/presentation/widgets/custom_task_component.dart features/notes/presentation/widgets/note_editor.dart`
Expected: No errors

- [ ] **Step 4: Commit**

```bash
git add lib/features/notes/presentation/widgets/custom_task_component.dart lib/features/notes/presentation/widgets/note_editor.dart
git commit -m "feat(notes): use onTaskCompleteWithDate in task component"
```

---

### Task 7: Update inbox_screen.dart

**Files:**
- Modify: `lib/features/notes/presentation/inbox_screen.dart:120-121`

- [ ] **Step 1: Add onTaskCompleteWithDate callback**

```dart
// Find the NoteEditor widget and add the new callback
NoteEditor(
  noteId: noteId,
  content: inbox.content,
  taskMetadata: tasksMap,
  delegate: NoteEditorDelegate(
    snapshotSave: (noteId, markdown, tasks) =>
        defaultSnapshotSave(repo, noteId, markdown, tasks),
    onHasContentChanged: (hasContent) {
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _hasContent = hasContent);
        });
      }
    },
    onTaskLongPress: (task, flushSnapshot) =>
        _openTaskActions(task, flushSnapshot),
    onTaskComplete: (taskId) =>
        ref.read(tasksRepositoryProvider).completeTask(taskId),
    onTaskReopen: (taskId) =>
        ref.read(tasksRepositoryProvider).reopenTask(taskId),
    onTaskCompleteWithDate: (taskId) async {
      final nextDue = await ref.read(tasksRepositoryProvider).completeTask(taskId);
      if (mounted) {
        AppMessenger.showTaskCompleted(
          context,
          nextDueDate: nextDue,
          onUndo: () async {
            await ref.read(tasksRepositoryProvider).reopenTask(taskId);
          },
        );
      }
      return nextDue;
    },
  ),
),
```

- [ ] **Step 2: Add import for AppMessenger**

```dart
import 'package:supanotes/shared/widgets/app_snackbar.dart';
```

- [ ] **Step 3: Verify no compilation errors**

Run: `cd lib && dart analyze features/notes/presentation/inbox_screen.dart`
Expected: No errors

- [ ] **Step 4: Commit**

```bash
git add lib/features/notes/presentation/inbox_screen.dart
git commit -m "feat(inbox): show snackbar on task completion"
```

---

### Task 8: Update note_editor_screen.dart

**Files:**
- Modify: `lib/features/notes/presentation/note_editor_screen.dart:170-171`

- [ ] **Step 1: Add onTaskCompleteWithDate callback**

```dart
// Find the NoteEditor widget and add the new callback
NoteEditor(
  noteId: widget.noteId,
  content: note.content,
  taskMetadata: tasksMap,
  hideCompleted: hideCompleted,
  collapseImages: note.collapseImages,
  isReadOnly: isReadOnly,
  delegate: NoteEditorDelegate(
    snapshotSave: (noteId, markdown, tasks) =>
        defaultSnapshotSave(repo, noteId, markdown, tasks),
    emptyNoteExit: (noteId) => defaultEmptyNoteExit(repo, noteId),
    onTaskLongPress: isReadOnly
        ? null
        : (task, flushSnapshot) =>
            _openTaskActions(task, flushSnapshot),
    onTaskComplete: (taskId) =>
        ref.read(tasksRepositoryProvider).completeTask(taskId),
    onTaskReopen: (taskId) =>
        ref.read(tasksRepositoryProvider).reopenTask(taskId),
    onTaskCompleteWithDate: (taskId) async {
      final nextDue = await ref.read(tasksRepositoryProvider).completeTask(taskId);
      if (mounted) {
        AppMessenger.showTaskCompleted(
          context,
          nextDueDate: nextDue,
          onUndo: () async {
            await ref.read(tasksRepositoryProvider).reopenTask(taskId);
          },
        );
      }
      return nextDue;
    },
    onUploadFile: isReadOnly
        ? null
        : (id, noteId, filePath, mimeType) =>
            ref.read(attachmentsRepositoryProvider).upload(
              id: id, noteId: noteId, file: File(filePath), mimeType: mimeType,
            ),
  ),
),
```

- [ ] **Step 2: Add import for AppMessenger**

```dart
import 'package:supanotes/shared/widgets/app_snackbar.dart';
```

- [ ] **Step 3: Verify no compilation errors**

Run: `cd lib && dart analyze features/notes/presentation/note_editor_screen.dart`
Expected: No errors

- [ ] **Step 4: Commit**

```bash
git add lib/features/notes/presentation/note_editor_screen.dart
git commit -m "feat(note-editor): show snackbar on task completion"
```

---

### Task 9: Run Full Analysis and Tests

**Files:**
- All modified files

- [ ] **Step 1: Run full Dart analysis**

Run: `cd lib && dart analyze`
Expected: No errors

- [ ] **Step 2: Run existing tests**

Run: `flutter test`
Expected: All tests pass

- [ ] **Step 3: Manual testing checklist**

1. Open a note with a non-recurring task
2. Click the task checkbox to complete it
3. Verify snackbar shows "Tarefa concluída!"
4. Click "Desfazer" button
5. Verify task reopens (status changes to "open")
6. Open a note with a daily recurring task
7. Complete the task
8. Verify snackbar shows "Tarefa concluída! Próx. ocorrência: [tomorrow's date]"
9. Wait 5 seconds
10. Verify snackbar auto-dismisses

- [ ] **Step 4: Final commit if any fixes needed**

```bash
git add -A
git commit -m "fix: address review feedback"
```

---

## Summary

| Task | Description | Files Modified |
|------|-------------|----------------|
| 1 | Update TasksDao.completeTask return type | `tasks_dao.dart` |
| 2 | Update TasksLocalRepository.completeTask | `tasks_local_repository.dart` |
| 3 | Update TasksRepository interface | `tasks_repository.dart` |
| 4 | Add showTaskCompleted to AppMessenger | `app_snackbar.dart` |
| 5 | Update NoteEditorDelegate | `note_editor_delegate.dart` |
| 6 | Update CustomTaskComponentBuilder | `custom_task_component.dart`, `note_editor.dart` |
| 7 | Update inbox_screen.dart | `inbox_screen.dart` |
| 8 | Update note_editor_screen.dart | `note_editor_screen.dart` |
| 9 | Run full analysis and tests | All files |
