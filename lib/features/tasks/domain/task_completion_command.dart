import 'package:supanotes/core/utils/recurrence.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';

class TaskSnapshot {
  final DateTime? dueDate;
  final bool hasTime;
  final TaskRecurrence? recurrence;

  const TaskSnapshot({
    this.dueDate,
    this.hasTime = false,
    this.recurrence,
  });
}

class TaskCompletionResult {
  final bool completed;
  final DateTime? nextDue;
  final DateTime completedAt;
  final DateTime? previousDue;
  final bool previousHasTime;

  const TaskCompletionResult({
    required this.completed,
    this.nextDue,
    required this.completedAt,
    this.previousDue,
    required this.previousHasTime,
  });
}

class TaskCompletionCommand {
  const TaskCompletionCommand(this._clock);
  final DateTime Function() _clock;

  TaskCompletionResult complete(TaskSnapshot task) {
    final completedAt = _clock().toUtc();
    final nextDue = task.recurrence == null
        ? null
        : nextDueDate(from: task.dueDate ?? completedAt, recurrence: task.recurrence!);
    return TaskCompletionResult(
      completed: nextDue == null,
      nextDue: nextDue,
      completedAt: completedAt,
      previousDue: task.dueDate,
      previousHasTime: task.hasTime,
    );
  }
}
