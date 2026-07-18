import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Deterministic, collision-resistant notification ID derived from
/// [userId] and [taskId].
///
/// Uses SHA-256 truncated to 31 bits (positive int32 range), which is
/// the maximum range supported by `flutter_local_notifications`.
///
/// This avoids the `String.hashCode` instability problem across
/// process restarts and platform channels.
int notificationIdForTask(String userId, String taskId) {
  final bytes = utf8.encode('$userId:$taskId');
  final digest = sha256.convert(bytes);
  final id = (digest.bytes[0] << 24) |
      (digest.bytes[1] << 16) |
      (digest.bytes[2] << 8) |
      digest.bytes[3];
  return id & 0x7fffffff;
}
