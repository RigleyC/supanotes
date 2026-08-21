import 'package:supanotes/features/tasks/domain/task_occurrence.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';

class TaskSnapshot {

  const TaskSnapshot({
    this.dueDate,
    this.hasTime = false,
    this.recurrence,
    this.completions = const {},
  });
  final DateTime? dueDate;
  final bool hasTime;
  final TaskRecurrence? recurrence;
  final Map<DateTime, DateTime> completions;
}

class TaskCompletionResult {

  const TaskCompletionResult({
    required this.completed,
    required this.completedAt, required this.previousHasTime, this.nextDue,
    this.previousDue,
    this.scheduledAt,
  });
  final bool completed;
  final DateTime? nextDue;
  final DateTime completedAt;
  final DateTime? previousDue;
  final bool previousHasTime;
  final DateTime? scheduledAt;
}

class TaskCompletionCommand {
  const TaskCompletionCommand(this._clock);
  final DateTime Function() _clock;

  TaskCompletionResult complete(TaskSnapshot task, {DateTime? scheduledAt}) {
    final transition = TaskOccurrencePolicy(clock: _clock).complete(
      dueDate: task.dueDate,
      hasTime: task.hasTime,
      recurrence: task.recurrence,
      completedAtByScheduledAt: task.completions,
      scheduledAt: scheduledAt,
    );
    return TaskCompletionResult(
      completed: transition.completed,
      nextDue: transition.nextDue,
      completedAt: transition.completedAt,
      previousDue: transition.previousDue,
      previousHasTime: transition.previousHasTime,
      scheduledAt: transition.scheduledAt,
    );
  }
}
