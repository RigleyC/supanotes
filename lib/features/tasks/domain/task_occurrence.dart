import 'package:supanotes/core/utils/recurrence.dart';

import 'task_recurrence.dart';

enum OccurrenceStatus { pending, overdue, completed }

class TaskOccurrence {
  const TaskOccurrence({
    required this.taskId,
    required this.scheduledAt,
    required this.status,
    this.completedAt,
  });

  final String taskId;
  final DateTime scheduledAt;
  final OccurrenceStatus status;
  final DateTime? completedAt;

  bool get isCompleted => status == OccurrenceStatus.completed;
  bool get isOverdue => status == OccurrenceStatus.overdue;
  bool get isPending => status == OccurrenceStatus.pending;
}

List<TaskOccurrence> buildOccurrences({
  required String taskId,
  required DateTime? anchor,
  required TaskRecurrence? recurrence,
  required bool hasTime,
  required DateTime now,
  required Set<DateTime> completedScheduledAts,
  int maxCount = 365,
}) {
  if (anchor == null) return [];

  if (recurrence == null) {
    final completedAt = _findCompletion(anchor, completedScheduledAts);
    return [
      TaskOccurrence(
        taskId: taskId,
        scheduledAt: anchor,
        status: completedAt != null
            ? OccurrenceStatus.completed
            : _isOverdue(anchor, now, hasTime)
            ? OccurrenceStatus.overdue
            : OccurrenceStatus.pending,
        completedAt: completedAt,
      ),
    ];
  }

  if (maxCount <= 0) return [];

  final currentDate = advanceRecurringDueDate(
    from: anchor,
    recurrence: recurrence,
    hasTime: hasTime,
    now: now,
  );
  final completedAt = _findCompletion(currentDate, completedScheduledAts);
  return [
    TaskOccurrence(
      taskId: taskId,
      scheduledAt: currentDate,
      status: completedAt != null
          ? OccurrenceStatus.completed
          : _isOverdue(currentDate, now, hasTime)
          ? OccurrenceStatus.overdue
          : OccurrenceStatus.pending,
      completedAt: completedAt,
    ),
  ];
}

DateTime nextOccurrenceDate({
  required DateTime from,
  required TaskRecurrence recurrence,
}) {
  return nextDueDate(from: from, recurrence: recurrence)!;
}

DateTime? _findCompletion(DateTime date, Set<DateTime> completedDates) {
  for (final d in completedDates) {
    if (d.year == date.year &&
        d.month == date.month &&
        d.day == date.day &&
        d.hour == date.hour &&
        d.minute == date.minute) {
      return d;
    }
  }
  return null;
}

bool _isOverdue(DateTime date, DateTime now, bool hasTime) {
  if (hasTime) {
    return date.isBefore(now);
  }
  final dateOnly = DateTime(date.year, date.month, date.day);
  final todayOnly = DateTime(now.year, now.month, now.day);
  return dateOnly.isBefore(todayOnly);
}
