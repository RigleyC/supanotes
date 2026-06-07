/// HTTP repository for the Telegram link flow.
///
/// Mirrors the three endpoints exposed by the backend's Telegram gateway:
///
///   * `GET /telegram/link`             → current link status.
///   * `POST /telegram/link-code`       → mint a one-shot pairing code.
///   * `DELETE /telegram/link`          → tear down the active link.
///
/// Like every other repository, [DioException]s are funnelled through
/// [fromDioError] so callers can `try`/`catch` against [ApiException]
/// without having to know about Dio.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/core/api/api_client.dart';
import 'package:supanotes/core/api/api_exceptions.dart';
import 'package:supanotes/core/di/providers.dart';

/// Snapshot of the user's current Telegram link state.
///
/// `linked == true` implies that both [chatId] and [username] are
/// populated; `linked == false` leaves them as `null`.
class TelegramLinkStatus {
  const TelegramLinkStatus({
    required this.linked,
    this.chatId,
    this.username,
  });

  final bool linked;
  final int? chatId;
  final String? username;

  factory TelegramLinkStatus.fromJson(Map<String, dynamic> json) {
    return TelegramLinkStatus(
      linked: (json['linked'] as bool?) ?? false,
      chatId: json['chat_id'] as int?,
      username: json['username'] as String?,
    );
  }
}

/// One-shot pairing code produced by `POST /telegram/link-code`.
///
/// The [expiresAt] timestamp is in UTC and parsed from the RFC-3339
/// string the backend returns.
class TelegramLinkCode {
  const TelegramLinkCode({
    required this.code,
    required this.expiresAt,
  });

  final String code;
  final DateTime expiresAt;

  factory TelegramLinkCode.fromJson(Map<String, dynamic> json) {
    return TelegramLinkCode(
      code: json['code'] as String,
      expiresAt: DateTime.parse(json['expires_at'] as String).toUtc(),
    );
  }

  /// True if the current wall clock is past the expiry. Computed against
  /// [DateTime.now] each time it is read so callers can use it inside a
  /// `setState`-driven countdown widget without caching.
  bool get isExpired => DateTime.now().toUtc().isAfter(expiresAt);

  /// Seconds remaining until the code expires. Clamps to zero on
  /// already-expired codes so UI code does not have to defend against
  /// negative durations.
  Duration get remaining {
    final diff = expiresAt.difference(DateTime.now().toUtc());
    return diff.isNegative ? Duration.zero : diff;
  }
}

abstract class ITelegramRepository {
  Future<TelegramLinkStatus> getLinkStatus();
  Future<TelegramLinkCode> generateLinkCode();
  Future<void> deleteLink();
}

class TelegramRepository implements ITelegramRepository {
  TelegramRepository({required ApiClient apiClient}) : _dio = apiClient.dio;

  final Dio _dio;

  /// `GET /telegram/link` → returns the current status. An unlinked
  /// account yields `linked: false` with no `chat_id` / `username` keys.
  Future<TelegramLinkStatus> getLinkStatus() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/telegram/link');
      final data = response.data;
      if (data == null) {
        throw const ServerException(
          message: 'Resposta vazia do servidor',
          statusCode: 500,
        );
      }
      return TelegramLinkStatus.fromJson(data);
    } on DioException catch (e) {
      throw fromDioError(e);
    }
  }

  /// `POST /telegram/link-code` → returns a fresh pairing code and its
  /// expiry. The backend enforces a per-user cooldown; the caller does
  /// not have to.
  Future<TelegramLinkCode> generateLinkCode() async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/telegram/link-code',
      );
      final data = response.data;
      if (data == null) {
        throw const ServerException(
          message: 'Resposta vazia do servidor',
          statusCode: 500,
        );
      }
      return TelegramLinkCode.fromJson(data);
    } on DioException catch (e) {
      throw fromDioError(e);
    }
  }

  /// `DELETE /telegram/link` → tears down the active link. Backend
  /// responds with 204 No Content.
  Future<void> deleteLink() async {
    try {
      await _dio.delete<dynamic>('/telegram/link');
    } on DioException catch (e) {
      throw fromDioError(e);
    }
  }
}

/// Single shared [TelegramRepository] wired to the app-wide
/// [apiClientProvider]. Stateless and safe to read from any consumer
/// that is authenticated.
final telegramRepositoryProvider = Provider<ITelegramRepository>((ref) {
  return TelegramRepository(apiClient: ref.watch(apiClientProvider));
});
