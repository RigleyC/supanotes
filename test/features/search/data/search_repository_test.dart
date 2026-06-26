import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/core/api/api_client.dart';
import 'package:supanotes/core/api/auth_interceptor.dart';
import 'package:supanotes/features/search/data/search_repository.dart';
import 'package:supanotes/features/search/domain/search_result_model.dart';

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
  group('SearchRepository', () {
    test('search returns list of SearchResultModel', () async {
      final client = _clientWithResponse(200, [
        {'ID': 'n-1', 'Title': 'Note 1', 'Excerpt': 'text 1', 'Score': 0.9},
        {'ID': 'n-2', 'Title': 'Note 2', 'Excerpt': 'text 2', 'Score': 0.8},
      ]);
      final repo = SearchRepository(apiClient: client);
      final results = await repo.search(query: 'test');
      expect(results.length, 2);
      expect(results.first.title, 'Note 1');
    });

    test('search returns empty list for empty query', () async {
      final client = _clientWithResponse(200, []);
      final repo = SearchRepository(apiClient: client);
      final results = await repo.search(query: '');
      expect(results, isEmpty);
    });

    test('search returns empty list for whitespace query', () async {
      final client = _clientWithResponse(200, []);
      final repo = SearchRepository(apiClient: client);
      final results = await repo.search(query: '   ');
      expect(results, isEmpty);
    });
  });
}
