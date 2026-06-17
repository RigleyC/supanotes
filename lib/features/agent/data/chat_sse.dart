import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import 'package:supanotes/core/api/api_client.dart';
import 'package:supanotes/core/api/api_exceptions.dart';

import 'package:supanotes/features/agent/domain/sse_chat_event.dart';

class ChatSSE {
  ChatSSE({required ApiClient apiClient}) : _api = apiClient;

  final ApiClient _api;
  CancelToken? _cancelToken;

  void cancel() {
    _cancelToken?.cancel();
    _cancelToken = null;
  }

  /// Opens an SSE stream to `POST /agent/chat/stream` and yields decoded
  /// SSEChatEvents until the server signals completion.
  Stream<SSEChatEvent> streamChat({
    required String sessionId,
    required String message,
  }) {
    _cancelToken = CancelToken();
    final controller = StreamController<SSEChatEvent>();

    _api.postStream(
      '/agent/chat/stream',
      data: <String, dynamic>{
        'session_id': sessionId,
        'content': message,
      },
      options: Options(receiveTimeout: const Duration(minutes: 5)),
      cancelToken: _cancelToken,
    ).then((response) async {
      final body = response.data as ResponseBody;
      final lines = body.stream
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      await for (final line in lines) {
        if (_cancelToken?.isCancelled ?? false) break;
        if (!line.startsWith('data: ')) continue;

        final jsonStr = line.substring(6);
        if (jsonStr.isEmpty) continue;

        try {
          final data = jsonDecode(jsonStr) as Map<String, dynamic>;
          final event = SSEChatEvent.fromJson(data);

          if (event.isError) {
            controller.addError(
              ApiException(message: event.errorMessage ?? event.data ?? 'Ocorreu um erro no stream'),
            );
            break;
          }

          controller.add(event);

          if (event.isDone) {
            break;
          }
        } catch (_) {
          // skip malformed lines
        }
      }
      await controller.close();
    }).catchError((Object e) {
      if (e is DioException) {
        if (CancelToken.isCancel(e)) return;
        controller.addError(fromDioError(e));
      } else {
        controller.addError(ApiException(message: e.toString()));
      }
      controller.close();
    });

    return controller.stream;
  }
}
