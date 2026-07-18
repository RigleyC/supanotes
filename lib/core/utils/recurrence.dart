import 'package:supanotes/features/tasks/domain/task_recurrence.dart';

/// Returns the next due date for a given [recurrence] rule starting from [from].
/// Returns `null` when the rule is not recognised.
DateTime? nextDueDate({required DateTime from, required TaskRecurrence recurrence}) {
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

DateTime _copyWith(
  DateTime date, {
  int? year,
  int? month,
  int? day,
}) {
  if (date.isUtc) {
    return DateTime.utc(
      year ?? date.year,
      month ?? date.month,
      day ?? date.day,
      date.hour,
      date.minute,
      date.second,
      date.millisecond,
      date.microsecond,
    );
  }
  return DateTime(
    year ?? date.year,
    month ?? date.month,
    day ?? date.day,
    date.hour,
    date.minute,
    date.second,
    date.millisecond,
    date.microsecond,
  );
}

/// Advances an overdue recurring [from] date forward to [today] by repeatedly
/// applying [nextDueDate].
DateTime catchUpDueDate({
  required DateTime from,
  required TaskRecurrence recurrence,
  required DateTime today,
}) {
  var currentDue = from;
  var next = nextDueDate(from: currentDue, recurrence: recurrence);
  while (next != null && next.isBefore(today)) {
    currentDue = next;
    next = nextDueDate(from: currentDue, recurrence: recurrence);
  }
  if (next != null && next.isAtSameMomentAs(today)) {
    currentDue = next;
  }
  return currentDue;
}
