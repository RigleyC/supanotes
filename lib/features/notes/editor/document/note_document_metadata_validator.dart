final class NoteDocumentMetadataValidator {
  const NoteDocumentMetadataValidator._();

  static void validate(String type, Map<String, dynamic> metadata) {
    void requireType(String key, bool condition) {
      if (metadata[key] != null && !condition) {
        throw FormatException('Invalid $key metadata for $type block');
      }
    }

    switch (type) {
      case 'rich_link':
        for (final key in const [
          'url',
          'title',
          'description',
          'imageUrl',
          'domain',
          'previewStatus',
          'faviconUrl',
          'siteName',
        ]) {
          requireType(key, metadata[key] is String);
        }
      case 'task':
        for (final key in const ['checked', 'recurrence']) {
          if (metadata.containsKey(key)) {
            throw FormatException(
              'Legacy $key metadata is not allowed; run the task document backfill',
            );
          }
        }
        requireType('isCompleted', metadata['isCompleted'] is bool);
        requireType('indent', metadata['indent'] is int);
        for (final key in const ['dueDate', 'recurrenceRule', 'reminder']) {
          requireType(key, metadata[key] is String);
        }
        requireType('hasTime', metadata['hasTime'] is bool);
        requireType('lastCompletedAt', metadata['lastCompletedAt'] is String);
        requireType('completions', metadata['completions'] is Map);

        final dueDate = metadata['dueDate'];
        if (dueDate is String && !_isCanonicalScheduledAt(dueDate)) {
          throw const FormatException(
            'Invalid dueDate metadata for task block: expected a canonical calendar timestamp without an offset',
          );
        }

        final recurrenceRule = metadata['recurrenceRule'];
        if (recurrenceRule is String &&
            !_canonicalRecurrenceRules.contains(recurrenceRule)) {
          throw const FormatException(
            'Invalid recurrenceRule metadata for task block',
          );
        }

        final reminder = metadata['reminder'];
        if (reminder is String && !_canonicalReminders.contains(reminder)) {
          throw const FormatException(
            'Invalid reminder metadata for task block',
          );
        }

        final lastCompletedAt = metadata['lastCompletedAt'];
        if (lastCompletedAt is String &&
            !_isCanonicalCompletedAt(lastCompletedAt)) {
          throw const FormatException(
            'Invalid lastCompletedAt metadata for task block: expected a UTC timestamp',
          );
        }

        final completions = metadata['completions'];
        if (completions is Map) {
          for (final entry in completions.entries) {
            if (entry.key is! String || entry.value is! String) {
              throw const FormatException(
                'Invalid completions metadata for task block',
              );
            }
            if (!_isCanonicalScheduledAt(entry.key as String) ||
                !_isCanonicalCompletedAt(entry.value as String)) {
              throw const FormatException(
                'Invalid completions metadata for task block',
              );
            }
          }
        }
      case 'bulletList' || 'orderedList':
        requireType('indent', metadata['indent'] is int);
      case 'attachment':
        for (final key in const [
          'attachmentId',
          'filename',
          'mimeType',
          'url',
        ]) {
          requireType(key, metadata[key] is String);
        }
        requireType('fileSize', metadata['fileSize'] is int);
    }
  }

  static const _canonicalRecurrenceRules = {
    'daily',
    'weekdays',
    'weekly',
    'monthly',
  };

  static const _canonicalReminders = {
    'at_time',
    '5m_before',
    '1h_before',
    '1d_before',
    '9am',
    '12pm',
    '6pm',
    '1d_before_9am',
  };

  static final _canonicalScheduledAtPattern = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})\.(\d{3})(\d{3})?$',
  );

  static final _canonicalCompletedAtPattern = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})\.(\d{3})(\d{3})?Z$',
  );

  static bool _isCanonicalScheduledAt(String value) {
    return _isCanonicalTimestamp(value, _canonicalScheduledAtPattern);
  }

  static bool _isCanonicalCompletedAt(String value) {
    return _isCanonicalTimestamp(value, _canonicalCompletedAtPattern);
  }

  static bool _isCanonicalTimestamp(String value, RegExp pattern) {
    final match = pattern.firstMatch(value);
    if (match == null) return false;

    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final hour = int.parse(match.group(4)!);
    final minute = int.parse(match.group(5)!);
    final second = int.parse(match.group(6)!);
    final millisecond = int.parse(match.group(7)!);
    final microsecond = int.parse(match.group(8) ?? '0');
    final parsed = DateTime.utc(
      year,
      month,
      day,
      hour,
      minute,
      second,
      millisecond,
      microsecond,
    );
    return parsed.year == year &&
        parsed.month == month &&
        parsed.day == day &&
        parsed.hour == hour &&
        parsed.minute == minute &&
        parsed.second == second &&
        parsed.millisecond == millisecond &&
        parsed.microsecond == microsecond;
  }
}
