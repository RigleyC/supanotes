import 'package:flutter/services.dart';

import 'package:supanotes/features/notes/share/domain/pending_share.dart';
import 'package:supanotes/features/notes/share/domain/share_note_index.dart';

abstract interface class NativeShareBridge {
  Future<void> publishNotesIndex(ShareNoteIndex index);

  Future<void> publishSessionCredentials({
    required String ownerUserId,
    required String accessToken,
    required String refreshToken,
    required String apiBaseUrl,
  });

  Future<void> clearShareSession();

  /// Asks the native side to resume durable pending deliveries
  /// (WorkManager on Android; a no-op until iOS background delivery lands).
  Future<void> retryPendingShares();

  Future<PendingShare?> readPendingShare();

  Future<void> clearPendingShare();
}

final class MethodChannelNativeShareBridge implements NativeShareBridge {
  MethodChannelNativeShareBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('com.supanotes/share');

  final MethodChannel _channel;

  @override
  Future<void> publishNotesIndex(ShareNoteIndex index) =>
      _channel.invokeMethod('publishNotesIndex', index.toJson());

  @override
  Future<void> publishSessionCredentials({
    required String ownerUserId,
    required String accessToken,
    required String refreshToken,
    required String apiBaseUrl,
  }) => _channel.invokeMethod('publishSessionCredentials', {
    'ownerUserId': ownerUserId,
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'apiBaseUrl': apiBaseUrl,
  });

  @override
  Future<void> retryPendingShares() =>
      _channel.invokeMethod('retryPendingShares');

  @override
  Future<void> clearShareSession() =>
      _channel.invokeMethod('clearShareSession');

  @override
  Future<PendingShare?> readPendingShare() async {
    final value = await _channel.invokeMethod<dynamic>('readPendingShare');
    if (value is! Map) return null;
    return PendingShare.fromMap(Map<String, dynamic>.from(value));
  }

  @override
  Future<void> clearPendingShare() =>
      _channel.invokeMethod('clearPendingShare');
}
