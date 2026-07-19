import 'package:flutter_riverpod/legacy.dart';
import 'package:supanotes/features/tasks/domain/task_model.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';
import 'package:supanotes/features/tasks/domain/task_reminder_option.dart';

class TaskMetadataState {
  DateTime? dueDate;
  bool hasTime;
  TaskRecurrence? recurrence;
  TaskReminderOption? reminder;

  TaskMetadataState({
    this.dueDate,
    this.hasTime = false,
    this.recurrence,
    this.reminder,
  });
}

TaskMetadataState taskMetadataStateFromModel(TaskModel task) {
  return TaskMetadataState(
    dueDate: task.dueDate,
    hasTime: task.hasTime,
    recurrence: task.recurrence,
    reminder: TaskReminderOption.fromYjsValue(task.reminder),
  );
}

final taskMetadataProvider =
    StateProvider.family<TaskMetadataState, String>((ref, taskId) {
  return TaskMetadataState();
});
