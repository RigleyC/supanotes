import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Deterministic platform IDs for task reminder occurrences.
///
/// The source discriminator, owner and occurrence are all part of the hash.
/// This prevents an independent task and a note block with the same ID from
/// replacing one another, and lets a recurring task keep one notification per
/// scheduled occurrence.
class TaskNotificationId {
  const TaskNotificationId._();

  static int forTask({
    required String userId,
    required String taskId,
    required DateTime scheduledAt,
  }) => _hash('v2|$userId|task|$taskId|${scheduledAt.toIso8601String()}');

  static int forNote({
    required String userId,
    required String noteId,
    required String blockId,
    required DateTime scheduledAt,
  }) => _hash(
    'v2|$userId|note|$noteId|$blockId|${scheduledAt.toIso8601String()}',
  );

  /// The pre-source-aware ID used by releases before standalone tasks.
  /// Keep this only for one-way migration and stale platform cleanup.
  static int legacyForTask(String userId, String taskId) {
    return _hash('$userId:$taskId');
  }

  /// Note reminders used the block ID in the same legacy namespace.
  static int legacyForNote(String userId, String blockId) {
    return legacyForTask(userId, blockId);
  }

  static int _hash(String value) {
    final bytes = utf8.encode(value);
    final digest = sha256.convert(bytes);
    final id =
        (digest.bytes[0] << 24) |
        (digest.bytes[1] << 16) |
        (digest.bytes[2] << 8) |
        digest.bytes[3];
    return id & 0x7fffffff;
  }
}

/// Backwards-compatible name for callers that only need a source-aware task
/// ID. New code should use [TaskNotificationId.forTask] directly.
int notificationIdForTask(
  String userId,
  String taskId, {
  DateTime? scheduledAt,
}) {
  if (scheduledAt == null) {
    return TaskNotificationId.legacyForTask(userId, taskId);
  }
  return TaskNotificationId.forTask(
    userId: userId,
    taskId: taskId,
    scheduledAt: scheduledAt,
  );
}
