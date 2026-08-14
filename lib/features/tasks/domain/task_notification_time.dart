/// Calculates the local platform notification time for a task occurrence.
DateTime? computeTaskNotificationTime({
  required DateTime due,
  required bool hasTime,
  required String? reminder,
}) {
  if (reminder == null) return null;

  final base = hasTime ? due : DateTime(due.year, due.month, due.day, 9);

  if (reminder == 'at_time') return base;

  switch (reminder) {
    case '5m_before':
      return base.subtract(const Duration(minutes: 5));
    case '1h_before':
      return base.subtract(const Duration(hours: 1));
    case '1d_before':
      return base.subtract(const Duration(days: 1));
    case '9am':
      return DateTime(due.year, due.month, due.day, 9);
    case '12pm':
      return DateTime(due.year, due.month, due.day, 12);
    case '6pm':
      return DateTime(due.year, due.month, due.day, 18);
    case '1d_before_9am':
      final dayBefore = due.subtract(const Duration(days: 1));
      return DateTime(dayBefore.year, dayBefore.month, dayBefore.day, 9);
    default:
      return base;
  }
}
