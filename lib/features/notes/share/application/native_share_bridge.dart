import 'package:flutter/services.dart';

import '../domain/share_note_index.dart';

abstract interface class NativeShareBridge {
  Future<void> publishNotesIndex(ShareNoteIndex index);

  Future<void> publishSessionCredentials({
    required String ownerUserId,
    required String accessToken,
    required String refreshToken,
  });

  Future<void> clearShareSession();

  Future<void> retryPendingShares();

  Future<String?> readPendingShare();

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
  }) => _channel.invokeMethod('publishSessionCredentials', {
    'ownerUserId': ownerUserId,
    'accessToken': accessToken,
    'refreshToken': refreshToken,
  });

  @override
  Future<void> clearShareSession() =>
      _channel.invokeMethod('clearShareSession');

  @override
  Future<void> retryPendingShares() =>
      _channel.invokeMethod('retryPendingShares');

  @override
  Future<String?> readPendingShare() =>
      _channel.invokeMethod<String>('readPendingShare');

  @override
  Future<void> clearPendingShare() =>
      _channel.invokeMethod('clearPendingShare');
}
