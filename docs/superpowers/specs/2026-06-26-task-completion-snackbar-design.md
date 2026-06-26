# Design: Task Completion Snackbar

**Date**: 2026-06-26  
**Status**: Approved  
**Author**: opencode

---

## Summary

Add a snackbar notification when a task is completed, showing "Tarefa concluída! Próx. ocorrência: [Date]" with an "Undo" button for accidental clicks.

---

## Requirements

1. Show snackbar when task is completed via UI (checkbox click)
2. Message: "Tarefa concluída!" or "Tarefa concluída! Próx. ocorrência: [Date]" for recurring tasks
3. "Desfazer" button that reopens the task
4. Auto-dismiss after 5 seconds
5. Undo calls `reopenTask(taskId)` to revert completion

---

## Architecture

### Current Flow

```
User clicks checkbox
  → CustomTaskComponentBuilder.setComplete(true)
    → TasksRepository.completeTask(taskId)
      → TasksLocalRepository.completeTask(taskId)
        → TasksDao.completeTask(taskId)
          → Calculates next due date (if recurring)
          → Updates task in database
```

### Proposed Flow

```
User clicks checkbox
  → CustomTaskComponentBuilder.setComplete(true)
    → TasksRepository.completeTask(taskId) → returns DateTime?
      → TasksLocalRepository.completeTask(taskId) → returns DateTime?
        → TasksDao.completeTask(taskId) → returns DateTime?
          → Calculates next due date (if recurring)
          → Updates task in database
          → Returns nextDueDate
    → Shows snackbar with returned date
```

---

## Implementation

### 1. Modify `TasksDao.completeTask`

**File**: `lib/core/database/daos/tasks_dao.dart`

Change return type from `Future<void>` to `Future<DateTime?>`:

```dart
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

### 2. Update `TasksLocalRepository.completeTask`

**File**: `lib/features/tasks/data/local/tasks_local_repository.dart`

```dart
Future<DateTime?> completeTask(String id) async {
  return await _dao.completeTask(id);
}
```

### 3. Update `TasksRepository.completeTask`

**File**: `lib/features/tasks/data/tasks_repository.dart`

```dart
@override
Future<DateTime?> completeTask(String id) => _local.completeTask(id);
```

Update interface:

```dart
abstract class ITasksRepository {
  // ...
  Future<DateTime?> completeTask(String id);
  // ...
}
```

### 4. Add `showTaskCompleted` to `AppMessenger`

**File**: `lib/shared/widgets/app_snackbar.dart`

```dart
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
```

### 5. Update `NoteEditorDelegate`

**File**: `lib/features/notes/presentation/controllers/note_editor_delegate.dart`

Add new callback:

```dart
final Future<DateTime?> Function(String taskId)? onTaskCompleteWithDate;
```

### 6. Update `CustomTaskComponentBuilder`

**File**: `lib/features/notes/presentation/widgets/custom_task_component.dart`

In `setComplete` callback, capture the returned date:

```dart
setComplete: (bool isComplete) async {
  // ... existing logic ...

  if (isComplete) {
    final nextDue = await onTaskCompleteWithDate?.call(node.id);
    // Snackbar will be shown by the caller
  } else {
    await onTaskReopen?.call(node.id);
  }
},
```

### 7. Update `inbox_screen.dart` and `note_editor_screen.dart`

**File**: `lib/features/notes/presentation/inbox_screen.dart`

```dart
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
```

Same pattern for `note_editor_screen.dart`.

---

## Testing

1. Complete a non-recurring task → snackbar shows "Tarefa concluída!"
2. Complete a daily recurring task → snackbar shows "Próx. ocorrência: [tomorrow]"
3. Complete a weekly recurring task → snackbar shows "Próx. ocorrência: [next week]"
4. Click "Desfazer" → task reopens, status changes to "open"
5. Wait 5 seconds → snackbar auto-dismisses
6. Complete task while another snackbar is visible → old snackbar hidden, new one shown

---

## Files to Modify

1. `lib/core/database/daos/tasks_dao.dart` - Return `DateTime?` from `completeTask`
2. `lib/features/tasks/data/local/tasks_local_repository.dart` - Propagate return type
3. `lib/features/tasks/data/tasks_repository.dart` - Update interface and implementation
4. `lib/shared/widgets/app_snackbar.dart` - Add `showTaskCompleted` method
5. `lib/features/notes/presentation/controllers/note_editor_delegate.dart` - Add callback
6. `lib/features/notes/presentation/widgets/custom_task_component.dart` - Use new callback
7. `lib/features/notes/presentation/inbox_screen.dart` - Implement callback
8. `lib/features/notes/presentation/note_editor_screen.dart` - Implement callback

---

## Out of Scope

- Snackbar for task completion via AI agent (MCP) - agent responses are shown separately
- Undo for task deletion
- Multiple undo levels
