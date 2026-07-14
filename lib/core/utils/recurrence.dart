import 'package:supanotes/features/tasks/domain/task_recurrence.dart';

/// Returns the next due date for a given [recurrence] rule starting from [from].
/// Returns `null` when the rule is not recognised.
DateTime? nextDueDate({required DateTime from, required TaskRecurrence recurrence}) {
  DateTime? raw;
  switch (recurrence) {
    case TaskRecurrence.daily:
      raw = from.add(const Duration(days: 1));
    case TaskRecurrence.weekdays:
      var day = from.add(const Duration(days: 1));
      while (day.weekday == DateTime.saturday || day.weekday == DateTime.sunday) {
        day = day.add(const Duration(days: 1));
      }
      raw = day;
    case TaskRecurrence.weekly:
      raw = from.add(const Duration(days: 7));
    case TaskRecurrence.monthly:
      final desiredMonth = from.month + 1;
      final overflow = desiredMonth > 12;
      final year = from.year + (overflow ? 1 : 0);
      final month = overflow ? 1 : desiredMonth;
      final lastDayOfTarget = DateTime(year, month + 1, 0).day;
      final day = from.day <= lastDayOfTarget ? from.day : lastDayOfTarget;
      raw = DateTime(year, month, day);
  }
  return raw;
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
