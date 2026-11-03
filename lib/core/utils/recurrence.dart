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

/// Returns the latest occurrence of the series anchored at [anchor] whose
/// calendar date is on or before the calendar date of [today], or `null` when
/// the anchor's own date is still in the future.
///
/// The series is the one produced by repeatedly applying [nextDueDate] from
/// [anchor] (monthly occurrences keep the anchor's day, clamped to the month
/// length). It is computed with calendar arithmetic in constant time instead
/// of stepping through every occurrence since the anchor, which made old
/// recurring tasks cost one local DateTime per elapsed day on every read.
DateTime? latestOccurrenceOnOrBefore({
  required DateTime anchor,
  required TaskRecurrence recurrence,
  required DateTime today,
}) {
  final anchorDay = _civilDay(anchor.year, anchor.month, anchor.day);
  final todayDay = _civilDay(today.year, today.month, today.day);
  final elapsed = todayDay - anchorDay;
  if (elapsed < 0) return null;
  switch (recurrence) {
    case TaskRecurrence.daily:
      return _copyWith(anchor, day: anchor.day + elapsed);
    case TaskRecurrence.weekly:
      return _copyWith(anchor, day: anchor.day + elapsed - elapsed % 7);
    case TaskRecurrence.weekdays:
      // The anchor always belongs to the series; later occurrences are the
      // weekdays after it. Step back from today to the nearest weekday.
      var offset = elapsed;
      while (offset > 0 && _isWeekend(anchorDay + offset)) {
        offset--;
      }
      return _copyWith(anchor, day: anchor.day + offset);
    case TaskRecurrence.monthly:
      var months =
          (today.year - anchor.year) * 12 + (today.month - anchor.month);
      var candidate = _monthlyOccurrence(anchor, months);
      if (_civilDay(candidate.year, candidate.month, candidate.day) >
          todayDay) {
        months--;
        candidate = _monthlyOccurrence(anchor, months);
      }
      return months <= 0 ? anchor : candidate;
  }
}

DateTime _monthlyOccurrence(DateTime anchor, int monthsAfter) {
  final monthIndex = anchor.month - 1 + monthsAfter;
  final year = anchor.year + monthIndex ~/ 12;
  final month = monthIndex % 12 + 1;
  final lastDay = DateTime.utc(year, month + 1, 0).day;
  final day = anchor.day <= lastDay ? anchor.day : lastDay;
  return _copyWith(anchor, year: year, month: month, day: day);
}

/// Days since 1970-01-01 for a calendar date, independent of time zones.
int _civilDay(int year, int month, int day) =>
    DateTime.utc(year, month, day).millisecondsSinceEpoch ~/
    Duration.millisecondsPerDay;

/// 1970-01-01 was a Thursday.
bool _isWeekend(int civilDay) {
  final weekday = (civilDay + 3) % 7 + 1;
  return weekday == DateTime.saturday || weekday == DateTime.sunday;
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
