extension DateTimeDateOnly on DateTime {
  /// Returns `true` if this DateTime represents the same calendar day as [other].
  bool isSameDayAs(DateTime other) {
    return year == other.year && month == other.month && day == other.day;
  }

  /// Returns a new DateTime with the time zeroed out.
  DateTime get startOfDay {
    return DateTime(year, month, day);
  }
}
