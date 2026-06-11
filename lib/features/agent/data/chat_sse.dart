import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import 'package:supanotes/core/api/api_client.dart';
import 'package:supanotes/core/api/api_exceptions.dart';

class ChatSSE {
  ChatSSE({required ApiClient apiClient}) : _api = apiClient;

  final ApiClient _api;
  CancelToken? _cancelToken;

  void cancel() {
    _cancelToken?.cancel();
    _cancelToken = null;
  }

  /// Opens an SSE stream to `POST /agent/chat/stream` and yields decoded
  /// delta events until the server signals completion.
  ///
  /// Each chunk is a `data: {...}\n\n` SSE line. Two shapes:
  ///   `{"delta":"text..."}`  → yield the text fragment
  ///   `{"done":true}`        → close the stream
  ///   `{"error":"..."}`      → yield then close
  Stream<String> streamChat({
    required String sessionId,
    required String message,
  }) {
    _cancelToken = CancelToken();
    final controller = StreamController<String>();

    _api.postStream(
      '/agent/chat/stream',
      data: <String, dynamic>{
        'session_id': sessionId,
        'content': message,
      },
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
          if (data.containsKey('delta')) {
            controller.add(data['delta'] as String);
          } else if (data['done'] == true) {
            break;
          } else if (data.containsKey('error')) {
            controller.addError(
              ApiException(message: data['error'] as String),
            );
            break;
          }
        } catch (_) {
          // skip malformed lines
        }
      }
      await controller.close();
    }).catchError((Object e) {
      if (e is DioException && CancelToken.isCancel(e)) return;
      controller.addError(fromDioError(e as DioException));
      controller.close();
    });

    return controller.stream;
  }
}
