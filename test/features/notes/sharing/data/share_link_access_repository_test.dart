import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/core/api/api_client.dart';
import 'package:supanotes/core/api/api_exceptions.dart';
import 'package:supanotes/features/notes/sharing/data/share_link_access_repository.dart';

import '../../../../helpers/auth_interceptor_test_helper.dart';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.response);

  final ResponseBody response;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<dynamic>? cancelFuture,
  ) async => response;
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

ResponseBody _response(int status, Object body) => ResponseBody.fromBytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {
    Headers.contentTypeHeader: ['application/json'],
  },
);

void main() {
  test('treats an authenticated 404 as no direct share', () async {
    final adapter = _StubAdapter(_response(404, {'error': 'not found'}));
    final repository = ShareLinkAccessRepository(_apiClient(adapter));

    expect(await repository.metadataFor('note-1'), isNull);
  });

  test('propagates an authenticated failure other than 404', () async {
    final adapter = _StubAdapter(_response(500, {'error': 'failed'}));
    final repository = ShareLinkAccessRepository(_apiClient(adapter));

    await expectLater(
      repository.metadataFor('note-1'),
      throwsA(isA<ServerException>()),
    );
  });
}
