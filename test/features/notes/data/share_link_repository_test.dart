import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/core/api/api_client.dart';
import 'package:supanotes/core/api/api_exceptions.dart';
import 'package:supanotes/features/notes/sharing/data/share_link_repository.dart';
import 'package:supanotes/features/notes/sharing/model/share_link_model.dart';

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
  test('gets the active link status', () async {
    final adapter = _StubAdapter(
      _jsonResponse(200, {'active': true, 'url': 'https://notes.test/s/abc'}),
    );
    final repository = ShareLinkRepository(_apiClient(adapter));

    final result = await repository.status('note-1');

    expect(
      result,
      const ShareLinkModel(active: true, url: 'https://notes.test/s/abc'),
    );
    expect(adapter.request.method, 'GET');
    expect(adapter.request.path, '/notes/note-1/share-link');
  });

  test('activates with replacement flag', () async {
    final adapter = _StubAdapter(
      _jsonResponse(200, {'active': true, 'url': 'https://notes.test/s/new'}),
    );
    final repository = ShareLinkRepository(_apiClient(adapter));

    await repository.activate('note-1', replace: true);

    expect(adapter.request.method, 'POST');
    expect(adapter.request.path, '/notes/note-1/share-link');
    expect(adapter.request.data, {'replace': true});
  });

  test('disables the link', () async {
    final adapter = _StubAdapter(_jsonResponse(204, {}));
    final repository = ShareLinkRepository(_apiClient(adapter));

    await repository.disable('note-1');

    expect(adapter.request.method, 'DELETE');
    expect(adapter.request.path, '/notes/note-1/share-link');
  });

  test('fails with a typed error for an invalid status response', () async {
    final adapter = _StubAdapter(_jsonResponse(200, {'url': 'missing-active'}));
    final repository = ShareLinkRepository(_apiClient(adapter));

    await expectLater(
      repository.status('note-1'),
      throwsA(isA<ServerException>()),
    );
  });
}
