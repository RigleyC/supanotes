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

/// Enumerates all scheduled occurrence dates for a recurring task within
/// the query window [from]..[to] (inclusive), starting from the [anchor]
/// date and applying [recurrence].
///
/// Returns an ordered list of dates. When [anchor] is null or [recurrence]
/// is null, returns an empty list.
///
/// The enumeration walks forward from [anchor] until it reaches [to],
/// capping at [maxCount] occurrences to avoid infinite loops.
List<DateTime> enumerateOccurrences({
  required DateTime? anchor,
  required TaskRecurrence? recurrence,
  required DateTime from,
  required DateTime to,
  int maxCount = 365,
}) {
  if (anchor == null || recurrence == null) return [];
  if (to.isBefore(from)) return [];

  final results = <DateTime>[];
  var current = anchor;

  // Phase 1: advance from anchor to the first occurrence >= from
  // (separate counter so far-past anchors don't consume the result budget)
  for (var i = 0; i < maxCount; i++) {
    if (!current.isBefore(from)) break;
    final next = nextDueDate(from: current, recurrence: recurrence);
    if (next == null || next.isAtSameMomentAs(current)) break;
    current = next;
  }

  // Phase 2: collect occurrences within the query window
  for (var i = 0; i < maxCount; i++) {
    if (current.isBefore(from) || current.isAfter(to)) break;
    results.add(current);
    final next = nextDueDate(from: current, recurrence: recurrence);
    if (next == null || next.isAtSameMomentAs(current)) break;
    current = next;
  }

  return results;
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
