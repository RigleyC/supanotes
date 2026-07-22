import 'package:supanotes/features/tasks/domain/task_recurrence.dart';
import 'package:supanotes/features/tasks/domain/task_occurrence.dart';

class TaskSnapshot {
  final DateTime? dueDate;
  final bool hasTime;
  final TaskRecurrence? recurrence;

  const TaskSnapshot({this.dueDate, this.hasTime = false, this.recurrence});
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

    // A recurring task remains open, but its due date moves to the next
    // occurrence. The completion history retains the completed occurrence.
    final occurrenceDate =
        scheduledAt ?? task.dueDate ?? DateTime(now.year, now.month, now.day);
    return TaskCompletionResult(
      completed: false,
      nextDue: nextOccurrenceDate(
        from: occurrenceDate,
        recurrence: task.recurrence!,
      ),
      completedAt: completedAt,
      previousDue: task.dueDate,
      previousHasTime: task.hasTime,
      scheduledAt: occurrenceDate,
    );
  }
}
