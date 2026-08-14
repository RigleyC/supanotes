import 'package:supanotes/features/tasks/domain/task_recurrence.dart';

/// Returns the next due date for a given [recurrence] rule starting from [from].
/// Returns `null` when the rule is not recognised.
DateTime? nextDueDate({
  required DateTime from,
  required TaskRecurrence recurrence,
  int? anchorDay,
}) {
  DateTime? raw;
  switch (recurrence) {
    case TaskRecurrence.daily:
      raw = _copyWith(from, day: from.day + 1);
    case TaskRecurrence.weekdays:
      var day = _copyWith(from, day: from.day + 1);
      while (day.weekday == DateTime.saturday ||
          day.weekday == DateTime.sunday) {
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
      final desiredDay = anchorDay ?? from.day;
      final day = desiredDay <= lastDayOfTarget ? desiredDay : lastDayOfTarget;
      raw = _copyWith(from, year: year, month: month, day: day);
  }
  return raw;
}

/// Returns the latest occurrence that has started at [now].
///
/// A missed occurrence is not kept as a permanent backlog. The task advances
/// when the next scheduled date is reached, while the current occurrence can
/// still be overdue until its following occurrence starts.
DateTime advanceRecurringDueDate({
  required DateTime from,
  required TaskRecurrence recurrence,
  required bool hasTime,
  DateTime? now,
  DateTime? anchor,
}) {
  final effectiveNow = now ?? DateTime.now();
  final today = DateTime(
    effectiveNow.year,
    effectiveNow.month,
    effectiveNow.day,
  );
  var current = from;
  final anchorDay = anchor?.day ?? from.day;

  for (var i = 0; i < 10000; i++) {
    final next = nextDueDate(
      from: current,
      recurrence: recurrence,
      anchorDay: anchorDay,
    );
    if (next == null || next.isAtSameMomentAs(current)) break;

    final hasStarted = hasTime
        ? !next.isAfter(effectiveNow)
        : !DateTime(next.year, next.month, next.day).isAfter(today);
    if (!hasStarted) break;
    current = next;
  }

  return current;
}

DateTime _copyWith(DateTime date, {int? year, int? month, int? day}) {
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

  final firstOccurrence = _advanceToWindowStart(
    current: anchor,
    recurrence: recurrence,
    from: from,
    maxCount: maxCount,
    anchorDay: anchor.day,
  );
  return _collectWindowOccurrences(
    current: firstOccurrence,
    recurrence: recurrence,
    from: from,
    to: to,
    maxCount: maxCount,
    anchorDay: anchor.day,
  );
}

DateTime _advanceToWindowStart({
  required DateTime current,
  required TaskRecurrence recurrence,
  required DateTime from,
  required int maxCount,
  required int anchorDay,
}) {
  // A separate counter keeps far-past anchors from consuming the result budget.
  for (var i = 0; i < maxCount; i++) {
    if (!current.isBefore(from)) break;
    final next = nextDueDate(
      from: current,
      recurrence: recurrence,
      anchorDay: anchorDay,
    );
    if (next == null || next.isAtSameMomentAs(current)) break;
    current = next;
  }
  return current;
}

List<DateTime> _collectWindowOccurrences({
  required DateTime current,
  required TaskRecurrence recurrence,
  required DateTime from,
  required DateTime to,
  required int maxCount,
  required int anchorDay,
}) {
  final results = <DateTime>[];
  for (var i = 0; i < maxCount; i++) {
    if (current.isBefore(from) || current.isAfter(to)) break;
    results.add(current);
    final next = nextDueDate(
      from: current,
      recurrence: recurrence,
      anchorDay: anchorDay,
    );
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
  DateTime? anchor,
}) {
  return advanceRecurringDueDate(
    from: from,
    recurrence: recurrence,
    hasTime: false,
    now: today,
    anchor: anchor,
  );
}
