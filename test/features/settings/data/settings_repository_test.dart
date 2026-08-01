import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/core/api/api_client.dart';
import 'package:supanotes/core/api/api_exceptions.dart';
import 'package:supanotes/core/api/auth_interceptor.dart';
import 'package:supanotes/features/settings/data/settings_repository.dart';
import '../../../helpers/auth_interceptor_test_helper.dart';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.response);

  final ResponseBody response;
  late RequestOptions request;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<dynamic>? cancelFuture,
  ) async {
    request = options;
    return response;
  }
}

ResponseBody _jsonResponse(int status, Object body) {
  return ResponseBody.fromBytes(
    utf8.encode(jsonEncode(body)),
    status,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
    },
  );
}

ApiClient _apiClient(_StubAdapter adapter) {
  final dio = Dio()..httpClientAdapter = adapter;
  final interceptor = buildTestAuthInterceptor(
    getAccessToken: () async => null,
    getRefreshToken: () async => null,
    saveTokens: ({required accessToken, required refreshToken}) async {},
    onAuthFailure: () async {},
    onRefresh: (_) async => null,
    replay: (options) => dio.fetch<dynamic>(options),
  );
  return ApiClient.test(authInterceptor: interceptor, dio: dio);
}

void main() {
  test('reads the token field returned by the backend', () async {
    final adapter = _StubAdapter(
      _jsonResponse(201, {'token': 'sn_mcp_test-token'}),
    );
    final repository = SettingsRepository(apiClient: _apiClient(adapter));

    final token = await repository.generateMcpToken();

    expect(token, 'sn_mcp_test-token');
    expect(adapter.request.method, 'POST');
    expect(adapter.request.path, '/auth/mcp-token');
  });

  test('returns a typed server error when the token is absent', () async {
    final adapter = _StubAdapter(_jsonResponse(201, {'id': 'token-id'}));
    final repository = SettingsRepository(apiClient: _apiClient(adapter));

    await expectLater(
      repository.generateMcpToken(),
      throwsA(isA<ServerException>()),
    );
  });
}
