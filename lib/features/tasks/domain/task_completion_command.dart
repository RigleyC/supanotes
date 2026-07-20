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
  final DateTime? scheduledAt;

  const TaskCompletionResult({
    required this.completed,
    this.nextDue,
    required this.completedAt,
    this.previousDue,
    required this.previousHasTime,
    this.scheduledAt,
  });
}

class TaskCompletionCommand {
  const TaskCompletionCommand(this._clock);
  final DateTime Function() _clock;

  TaskCompletionResult complete(TaskSnapshot task, {DateTime? scheduledAt}) {
    final now = _clock();
    final completedAt = now.toUtc();

    if (task.recurrence == null) {
      return TaskCompletionResult(
        completed: true,
        nextDue: null,
        completedAt: completedAt,
        previousDue: task.dueDate,
        previousHasTime: task.hasTime,
        scheduledAt: scheduledAt,
      );
    }

    // For recurring tasks, the template stays open and its dueDate is
    // not advanced. The completion records which occurrence was completed
    // (scheduledAt). The occurrence date defaults to the task's dueDate
    // or, if missing, today's start.
    final occurrenceDate = scheduledAt ?? task.dueDate ??
        DateTime(now.year, now.month, now.day);
    return TaskCompletionResult(
      completed: false,
      nextDue: null,
      completedAt: completedAt,
      previousDue: task.dueDate,
      previousHasTime: task.hasTime,
      scheduledAt: occurrenceDate,
    );
  }
}
