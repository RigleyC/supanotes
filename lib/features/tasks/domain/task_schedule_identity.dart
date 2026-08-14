/// Returns the stable identity of a scheduled task occurrence.
///
/// A scheduled occurrence is a calendar value, not an instant. The key keeps
/// the wall-clock components and intentionally has no timezone offset. The
/// completion value is stored separately as a UTC instant.
String scheduledAtKey(DateTime value, {required bool hasTime}) {
  return canonicalScheduledAt(value, hasTime: hasTime).toIso8601String();
}

/// Normalizes a scheduled value for calendar comparisons.
DateTime canonicalScheduledAt(DateTime value, {required bool hasTime}) {
  return DateTime(
    value.year,
    value.month,
    value.day,
    hasTime ? value.hour : 0,
    hasTime ? value.minute : 0,
    hasTime ? value.second : 0,
    hasTime ? value.millisecond : 0,
    hasTime ? value.microsecond : 0,
  );
}

/// Compares two schedule values without converting either value through UTC.
bool sameScheduledAt(DateTime left, DateTime right, {required bool hasTime}) {
  return scheduledAtKey(left, hasTime: hasTime) ==
      scheduledAtKey(right, hasTime: hasTime);
}

/// Parses a document schedule value into the canonical local wall-clock form.
DateTime? parseScheduledAt(String? value, {required bool hasTime}) {
  final parsed = DateTime.tryParse(value ?? '');
  return parsed == null ? null : canonicalScheduledAt(parsed, hasTime: hasTime);
}

/// Reads and canonicalizes recurring completion metadata at a document edge.
Map<DateTime, DateTime> readScheduledCompletions(
  Object? value, {
  required bool hasTime,
}) {
  if (value is! Map) return const {};
  final result = <DateTime, DateTime>{};
  for (final entry in value.entries) {
    if (entry.key is! String || entry.value is! String) continue;
    final scheduledAt = parseScheduledAt(entry.key as String, hasTime: hasTime);
    final completedAt = DateTime.tryParse(entry.value as String);
    if (scheduledAt == null || completedAt == null) continue;

    final previous = result[scheduledAt];
    if (previous == null || completedAt.isAfter(previous)) {
      result[scheduledAt] = completedAt;
    }
  }
  return result;
}
