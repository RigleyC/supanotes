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

  final todayStart = DateTime(now.year, now.month, now.day);
  final futureLimit = todayStart.add(const Duration(days: 30));

  final allDates = _enumerateOccurrencesBounded(
    anchor: anchor,
    recurrence: recurrence,
    from: anchor,
    to: futureLimit,
    maxCount: maxCount,
  );

  if (allDates.isEmpty) return [];

  final result = <TaskOccurrence>[];
  for (final date in allDates) {
    final completedAt = _findCompletion(date, completedScheduledAts);
    result.add(TaskOccurrence(
      taskId: taskId,
      scheduledAt: date,
      status: completedAt != null
          ? OccurrenceStatus.completed
          : _isOverdue(date, now, hasTime)
              ? OccurrenceStatus.overdue
              : OccurrenceStatus.pending,
      completedAt: completedAt,
    ));
  }

  return result;
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

List<DateTime> _enumerateOccurrencesBounded({
  required DateTime anchor,
  required TaskRecurrence recurrence,
  required DateTime from,
  required DateTime to,
  int maxCount = 365,
}) {
  if (to.isBefore(from)) return [];

  final results = <DateTime>[];
  var current = anchor;

  for (var i = 0; i < maxCount; i++) {
    if (!current.isBefore(from)) break;
    final next = _nextDueDate(from: current, recurrence: recurrence);
    if (next == null || next.isAtSameMomentAs(current)) break;
    current = next;
  }

  for (var i = 0; i < maxCount; i++) {
    if (current.isBefore(from) || current.isAfter(to)) break;
    results.add(current);
    final next = _nextDueDate(from: current, recurrence: recurrence);
    if (next == null || next.isAtSameMomentAs(current)) break;
    current = next;
  }

  return results;
}

DateTime _copyWith(DateTime date, {int? year, int? month, int? day}) {
  if (date.isUtc) {
    return DateTime.utc(
      year ?? date.year,
      month ?? date.month,
      day ?? date.day,
      date.hour,
      date.minute,
    );
  }
  return DateTime(
    year ?? date.year,
    month ?? date.month,
    day ?? date.day,
    date.hour,
    date.minute,
  );
}

DateTime? _nextDueDate({required DateTime from, required TaskRecurrence recurrence}) {
  DateTime? raw;
  switch (recurrence) {
    case TaskRecurrence.daily:
      raw = _copyWith(from, day: from.day + 1);
    case TaskRecurrence.weekdays:
      var day = _copyWith(from, day: from.day + 1);
      while (day.weekday == DateTime.saturday || day.weekday == DateTime.sunday) {
        day = _copyWith(day, day: day.day + 1);
      }
      raw = day;
    case TaskRecurrence.weekly:
      raw = _copyWith(from, day: from.day + 7);
    case TaskRecurrence.monthly:
      final desiredMonth = from.month + 1;
      final overflow = desiredMonth > 12;
      final year = from.year + (overflow ? 1 : 0);
      final month = overflow ? 1 : desiredMonth;
      final lastDayOfTarget = DateTime(year, month + 1, 0).day;
      final day = from.day <= lastDayOfTarget ? from.day : lastDayOfTarget;
      raw = _copyWith(from, year: year, month: month, day: day);
  }
  return raw;
}
