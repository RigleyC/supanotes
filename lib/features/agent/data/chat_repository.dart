/// HTTP repository for the agent chat endpoints.
///
/// Sits next to [AgentRepository] (which handles the inbox-organization
/// flow) so the FE-5 and FE-7 features can evolve independently while
/// sharing the same [ApiClient] and exception mapping.
///
/// Endpoints consumed (see `backend/internal/agent/handler.go`):
///   * `POST /api/v1/agent/chat`
///   * `GET  /api/v1/agent/messages?session_id=<uuid>`
///   * `DELETE /api/v1/agent/messages?session_id=<uuid>`
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/core/api/api_client.dart';
import 'package:supanotes/core/api/api_exceptions.dart';
import 'package:supanotes/core/di/providers.dart';

import '../domain/message_model.dart';
import '../domain/tool_confirmation.dart';

abstract class IChatRepository {
  Future<String> sendMessage({required String sessionId, required String message});
  Future<List<MessageModel>> getHistory(String sessionId);
  Future<void> clearHistory(String sessionId);
  Future<ToolConfirmationResolution> resolveToolConfirmation({
    required String confirmationId,
    required bool approved,
  });
}

class ChatRepository implements IChatRepository {
  ChatRepository({required ApiClient apiClient}) : _api = apiClient;

  final ApiClient _api;

  /// `POST /agent/chat` → returns the assistant reply body.
  @override
  Future<String> sendMessage({
    required String sessionId,
    required String message,
  }) async {
    try {
      final response = await _api.post<Map<String, dynamic>>(
        '/agent/chat',
        data: <String, dynamic>{
          'session_id': sessionId,
          'content': message,
        },
      );
      final data = response.data;
      if (data == null || data['response'] is! String) {
        throw const ServerException(
          message: 'Resposta inválida do servidor',
          statusCode: 500,
        );
      }
      return data['response'] as String;
    } on DioException catch (e) {
      throw fromDioError(e);
    }
  }

  /// `GET /agent/messages?session_id=<uuid>` → persisted history.
  @override
  Future<List<MessageModel>> getHistory(String sessionId) async {
    try {
      final response = await _api.get<List<dynamic>>(
        '/agent/messages',
        queryParameters: <String, dynamic>{'session_id': sessionId},
      );
      final data = response.data;
      if (data == null) return const <MessageModel>[];
      return data
          .whereType<Map<String, dynamic>>()
          .map(MessageModel.fromJson)
          .toList(growable: false);
    } on DioException catch (e) {
      throw fromDioError(e);
    }
  }

  /// `POST /agent/tool-confirmations/:id/resolve` → approve/cancel a pending tool.
  @override
  Future<ToolConfirmationResolution> resolveToolConfirmation({
    required String confirmationId,
    required bool approved,
  }) async {
    try {
      final response = await _api.post<Map<String, dynamic>>(
        '/agent/tool-confirmations/$confirmationId/resolve',
        data: <String, dynamic>{'approved': approved},
      );
      final data = response.data;
      if (data == null) {
        throw const ServerException(
          message: 'Resposta vazia do servidor',
          statusCode: 500,
        );
      }
      return ToolConfirmationResolution.fromJson(data);
    } on DioException catch (e) {
      throw fromDioError(e);
    }
  }

  /// `DELETE /agent/messages?session_id=<uuid>` → wipe history.
  @override
  Future<void> clearHistory(String sessionId) async {
    try {
      await _api.delete<dynamic>(
        '/agent/messages',
        queryParameters: <String, dynamic>{'session_id': sessionId},
      );
    } on DioException catch (e) {
      throw fromDioError(e);
    }
  }
}

final chatRepositoryProvider = Provider.autoDispose<IChatRepository>((ref) {
  return ChatRepository(apiClient: ref.watch(apiClientProvider));
});
