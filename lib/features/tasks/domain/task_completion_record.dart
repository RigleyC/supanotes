import 'package:supanotes/features/tasks/domain/task_schedule_identity.dart';

/// A completion archived before its task schedule changed.
///
/// `scheduledAt` is nullable for tasks completed without a due date; `hasTime`
/// preserves whether a non-null calendar value represented a time of day.
class TaskCompletionRecord {
  const TaskCompletionRecord({
    required this.scheduledAt,
    required this.hasTime,
    required this.completedAt,
  });

  final DateTime? scheduledAt;
  final bool hasTime;
  final DateTime completedAt;

  Map<String, Object?> toJson() => {
    'scheduledAt': scheduledAt == null
        ? null
        : scheduledAtKey(scheduledAt!, hasTime: hasTime),
    'hasTime': hasTime,
    'completedAt': completedAt.toUtc().toIso8601String(),
  };

  factory TaskCompletionRecord.fromJson(Map<String, dynamic> json) {
    final rawScheduledAt = json['scheduledAt'];
    if (rawScheduledAt != null && rawScheduledAt is! String) {
      throw const FormatException('invalid archived scheduledAt');
    }
    final rawCompletedAt = json['completedAt'];
    if (rawCompletedAt is! String || !rawCompletedAt.endsWith('Z')) {
      throw const FormatException('invalid archived completion timestamp');
    }
    final completedAt = DateTime.tryParse(rawCompletedAt);
    if (completedAt == null ||
        completedAt.toUtc().toIso8601String() != rawCompletedAt) {
      throw const FormatException('invalid archived completion timestamp');
    }
    final rawHasTime = json['hasTime'];
    if (rawHasTime is! bool) {
      throw const FormatException('invalid archived hasTime');
    }
    final hasTime = rawHasTime;
    final scheduledAt = rawScheduledAt == null
        ? null
        : parseScheduledAt(rawScheduledAt as String, hasTime: hasTime);
    if (rawScheduledAt != null &&
        (scheduledAt == null ||
            scheduledAtKey(scheduledAt, hasTime: hasTime) != rawScheduledAt)) {
      throw const FormatException('invalid archived scheduledAt');
    }
    return TaskCompletionRecord(
      scheduledAt: scheduledAt,
      hasTime: hasTime,
      completedAt: completedAt,
    );
  }
}

/// Archives the active completion data before a task schedule changes.
///
/// Independent tasks and note tasks store their active completions in
/// different shapes, but the archived occurrence record has the same meaning
/// for both sources.
/// Combines prior history with active completion fields before a schedule edit.
List<TaskCompletionRecord> archiveTaskCompletionHistory({
  required Iterable<TaskCompletionRecord> history,
  required Map<String, Object?> completions,
  required DateTime? scheduledAt,
  required bool hasTime,
  required bool isCompleted,
  DateTime? lastCompletedAt,
}) {
  final records = [...history];
  for (final entry in completions.entries) {
    final occurrence = parseScheduledAt(entry.key, hasTime: hasTime);
    final rawCompletedAt = entry.value;
    final completed = rawCompletedAt is String
        ? DateTime.tryParse(rawCompletedAt)
        : null;
    if (occurrence == null || completed == null) continue;
    records.add(
      TaskCompletionRecord(
        scheduledAt: occurrence,
        hasTime: hasTime,
        completedAt: completed.toUtc(),
      ),
    );
  }
  if (isCompleted && lastCompletedAt != null) {
    records.add(
      TaskCompletionRecord(
        scheduledAt: scheduledAt,
        hasTime: hasTime,
        completedAt: lastCompletedAt.toUtc(),
      ),
    );
  }
  return deduplicateTaskCompletionHistory(records);
}

/// Returns one record for each unique scheduled occurrence and completion time.
List<TaskCompletionRecord> deduplicateTaskCompletionHistory(
  Iterable<TaskCompletionRecord> entries,
) {
  final unique = <String, TaskCompletionRecord>{};
  for (final entry in entries) {
    final scheduled = entry.scheduledAt == null
        ? 'null'
        : scheduledAtKey(entry.scheduledAt!, hasTime: entry.hasTime);
    final completedAt = entry.completedAt.toUtc().toIso8601String();
    final key = '$scheduled|${entry.hasTime}|$completedAt';
    unique[key] = entry;
  }
  return List.unmodifiable(unique.values);
}

/// Parses and deduplicates a serialized task completion history value.
List<TaskCompletionRecord> parseTaskCompletionHistory(Object? value) {
  if (value == null) return const [];
  if (value is! List) {
    throw const FormatException('completionHistory must be an array');
  }
  return deduplicateTaskCompletionHistory([
    for (final entry in value)
      if (entry is Map)
        TaskCompletionRecord.fromJson(entry.cast<String, dynamic>())
      else
        throw const FormatException('invalid archived completion record'),
  ]);
}
