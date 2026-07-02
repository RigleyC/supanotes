extension DateTimeDateOnly on DateTime {
  /// Returns `true` if this DateTime represents the same calendar day as [other].
  bool isSameDayAs(DateTime other) {
    return year == other.year && month == other.month && day == other.day;
  }

  /// Returns a new DateTime with the time zeroed out.
  DateTime get startOfDay {
    return DateTime(year, month, day);
  }

  /// Returns true if this date is Today, Tomorrow, or 7 days from now.
  bool isQuickPick() {
    final today = DateTime.now().startOfDay;
    final tomorrow = today.add(const Duration(days: 1));
    final nextWeek = today.add(const Duration(days: 7));
    return isSameDayAs(today) || isSameDayAs(tomorrow) || isSameDayAs(nextWeek);
  }
}
