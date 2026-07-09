import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/core/api/api_client.dart';
import 'package:supanotes/core/api/auth_interceptor.dart';
import 'package:supanotes/features/settings/data/settings_repository.dart';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.responder);
  final Future<ResponseBody> Function(RequestOptions options) responder;
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<dynamic>? cancelFuture,
  ) async {
    return responder(options);
  }
}

AuthInterceptor _stubInterceptor() {
  return AuthInterceptor(
    getAccessToken: () async => null,
    getRefreshToken: () async => null,
    saveTokens: ({required accessToken, required refreshToken}) async {},
    onAuthFailure: () async {},
    onRefresh: (token) async => null,
    replay: (options) async => Response(
      requestOptions: options,
      data: '{}',
      statusCode: 200,
    ),
  );
}

ApiClient _clientWithResponse(int statusCode, dynamic data) {
  final dio = Dio()..options.baseUrl = 'http://localhost';
  dio.httpClientAdapter = _StubAdapter((_) async {
    return ResponseBody.fromString(
      jsonEncode(data),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  });
  return ApiClient.test(authInterceptor: _stubInterceptor(), dio: dio);
}

void main() {
  group('SettingsRepository', () {
    test('getSettings returns UserSettings', () async {
      final client = _clientWithResponse(200, {
        'timezone': 'America/Sao_Paulo',
        'created_at': '2025-01-01T00:00:00.000Z',
        'updated_at': '2025-06-01T00:00:00.000Z',
      });
      final repo = SettingsRepository(apiClient: client);
      final settings = await repo.getSettings();
      expect(settings.timezone, 'America/Sao_Paulo');
    });

    test('getSoul returns Soul', () async {
      final client = _clientWithResponse(200, {
        'personality': 'Be helpful.',
      });
      final repo = SettingsRepository(apiClient: client);
      final soul = await repo.getSoul();
      expect(soul.personality, 'Be helpful.');
    });

    test('getContexts returns list of UserContext', () async {
      final client = _clientWithResponse(200, [
        {
          'id': 'c-1',
          'slug': 'work',
          'name': 'Work',
          'created_at': '2025-01-01T00:00:00.000Z',
          'updated_at': '2025-06-01T00:00:00.000Z',
        },
      ]);
      final repo = SettingsRepository(apiClient: client);
      final contexts = await repo.getContexts();
      expect(contexts.length, 1);
      expect(contexts.first.name, 'Work');
    });

    test('createContext returns UserContext', () async {
      final client = _clientWithResponse(200, {
        'id': 'c-2',
        'slug': 'new-context',
        'name': 'New Context',
        'created_at': '2025-06-01T00:00:00.000Z',
        'updated_at': '2025-06-01T00:00:00.000Z',
      });
      final repo = SettingsRepository(apiClient: client);
      final ctx = await repo.createContext('New Context');
      expect(ctx.name, 'New Context');
      expect(ctx.slug, 'new-context');
    });
  });
}
