/// HTTP repository for agent chat (SSE streaming) endpoints.
library;

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/core/api/api_client.dart';
import 'package:supanotes/core/api/api_exceptions.dart';
import 'package:supanotes/core/di/providers.dart';

import '../domain/sse_chat_event.dart';

class AgentRepository {
  AgentRepository({required ApiClient apiClient}) : _api = apiClient;

  final ApiClient _api;

  Stream<SSEChatEvent> streamChat({required String sessionId, required String message}) async* {
    try {
      final response = await _api.postStream(
        '/agent/chat/stream',
        data: {'session_id': sessionId, 'message': message},
      );
      final body = response.data;
      if (body == null) return;

      String buffer = '';
      await for (final uint8list in body.stream) {
        buffer += String.fromCharCodes(uint8list);
        while (buffer.contains('\n')) {
          final lineEnd = buffer.indexOf('\n');
          final line = buffer.substring(0, lineEnd).trim();
          buffer = buffer.substring(lineEnd + 1);
          if (line.startsWith('data: ')) {
            final jsonStr = line.substring(6);
            if (jsonStr == '[DONE]') break;
            try {
              // ignore: avoid_dynamic_calls
              final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
              yield SSEChatEvent.fromJson(decoded);
            } catch (e) {
              debugPrint('agent_repository: failed to parse SSE event: $e');
            }
          }
        }
      }
    } on DioException catch (e) {
      throw fromDioError(e);
    }
  }
}

/// Single shared [AgentRepository] wired to the app-wide [apiClientProvider].
final agentRepositoryProvider = Provider.autoDispose<AgentRepository>((ref) {
  return AgentRepository(apiClient: ref.watch(apiClientProvider));
});
