import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supanotes/core/api/auth_interceptor.dart';
import 'package:supanotes/features/auth/data/auth_local_storage.dart';

class _MockAuthLocalStorage extends Mock implements AuthLocalStorage {}

class _AdapterHit {
  _AdapterHit(this.method, this.path, this.headers, this.body);
  final String method;
  final String path;
  final Map<String, String> headers;
  final String body;
}

class _TestAdapter implements HttpClientAdapter {
  _TestAdapter(this.responder);

  final Future<ResponseBody> Function(RequestOptions options) responder;

  final List<_AdapterHit> hits = [];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<dynamic>? cancelFuture,
  ) async {
    final body = await _readBody(requestStream);
    hits.add(
      _AdapterHit(
        options.method,
        options.path,
        options.headers.map((k, v) => MapEntry(k, v.toString())),
        body,
      ),
    );
    return responder(options);
  }

  static Future<String> _readBody(Stream<Uint8List>? stream) async {
    if (stream == null) return '';
    final chunks = <int>[];
    await for (final chunk in stream) {
      chunks.addAll(chunk);
    }
    return utf8.decode(chunks, allowMalformed: true);
  }
}

ResponseBody _jsonResponse(int status, Object body) {
  final bytes = utf8.encode(jsonEncode(body));
  return ResponseBody.fromBytes(
    bytes,
    status,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
    },
  );
}

DioException _dioError({
  required int status,
  required String path,
  required String method,
  String message = 'x',
}) {
  return DioException(
    requestOptions: RequestOptions(path: path, method: method),
    response: Response<dynamic>(
      requestOptions: RequestOptions(path: path, method: method),
      statusCode: status,
      data: <String, dynamic>{'error': message},
    ),
    type: DioExceptionType.badResponse,
  );
}

/// Build the [RefreshHandler] and [ReplayHandler] callbacks from a shared
/// [Dio] so tests can inspect [adapter] for both refresh and replay hits.
({
  RefreshHandler onRefresh,
  ReplayHandler replay,
}) _refreshCallbacks(Dio dio) {
  return (
    onRefresh: (token) async {
      try {
        final response = await dio.post<Map<String, dynamic>>(
          '/auth/refresh',
          data: {'refresh_token': token},
        );
        final data = response.data;
        if (data == null) return null;
        final at = data['access_token'] as String?;
        final rt = data['refresh_token'] as String?;
        if (at == null || rt == null) return null;
        return (accessToken: at, refreshToken: rt);
      } on DioException {
        return null;
      }
    },
    replay: (options) => dio.fetch<dynamic>(options),
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(
      RequestOptions(path: '/', method: 'GET'),
    );
  });

  group('AuthInterceptor.onRequest', () {
    test('attaches Authorization header when a token is stored', () async {
      final storage = _MockAuthLocalStorage();
      when(() => storage.getAccessToken()).thenAnswer((_) async => 'tok-1');
      final interceptor = AuthInterceptor(
        tokenStorage: storage,
        onAuthFailure: () async {},
        onRefresh: (_) async => null,
        replay: (_) => throw UnimplementedError('not used in this test'),
      );

      final capturedHeaders = <String, String>{};
      final adapter = _TestAdapter((options) async {
        capturedHeaders.addAll(
          options.headers.map((k, v) => MapEntry(k, v.toString())),
        );
        return _jsonResponse(200, {'ok': true});
      });
      final dio = Dio()..httpClientAdapter = adapter;
      dio.interceptors.add(interceptor);

      await dio.get<dynamic>('/notes');

      expect(capturedHeaders['Authorization'], 'Bearer tok-1');
    });

    test('attaches Authorization header even for /auth/* paths', () async {
      final storage = _MockAuthLocalStorage();
      when(() => storage.getAccessToken()).thenAnswer((_) async => 'tok-1');
      final interceptor = AuthInterceptor(
        tokenStorage: storage,
        onAuthFailure: () async {},
        onRefresh: (_) async => null,
        replay: (_) => throw UnimplementedError('not used in this test'),
      );

      final capturedHeaders = <String, String>{};
      final adapter = _TestAdapter((options) async {
        capturedHeaders.addAll(
          options.headers.map((k, v) => MapEntry(k, v.toString())),
        );
        return _jsonResponse(200, {'ok': true});
      });
      final dio = Dio()..httpClientAdapter = adapter;
      dio.interceptors.add(interceptor);

      await dio.post<dynamic>('/auth/login', data: {'email': 'a@b'});

      expect(capturedHeaders['Authorization'], 'Bearer tok-1');
    });

    test('does not attach Authorization when storage is empty', () async {
      final storage = _MockAuthLocalStorage();
      when(() => storage.getAccessToken()).thenAnswer((_) async => null);
      final interceptor = AuthInterceptor(
        tokenStorage: storage,
        onAuthFailure: () async {},
        onRefresh: (_) async => null,
        replay: (_) => throw UnimplementedError('not used in this test'),
      );

      final capturedHeaders = <String, String>{};
      final adapter = _TestAdapter((options) async {
        capturedHeaders.addAll(
          options.headers.map((k, v) => MapEntry(k, v.toString())),
        );
        return _jsonResponse(200, {'ok': true});
      });
      final dio = Dio()..httpClientAdapter = adapter;
      dio.interceptors.add(interceptor);

      await dio.get<dynamic>('/notes');

      expect(capturedHeaders.containsKey('Authorization'), isFalse);
    });
  });

  group('AuthInterceptor.onError (401 refresh flow)', () {
    test(
        'on 401, calls /auth/refresh and replays the original request with '
        'the new token', () async {
      final storage = _MockAuthLocalStorage();
      when(() => storage.getAccessToken())
          .thenAnswer((_) async => 'old-access');
      when(() => storage.getRefreshToken())
          .thenAnswer((_) async => 'old-refresh');
      when(() => storage.getUserId()).thenAnswer((_) async => 'user-1');
      when(() => storage.saveTokens(
            accessToken: any(named: 'accessToken'),
            refreshToken: any(named: 'refreshToken'),
            userId: any(named: 'userId'),
          )).thenAnswer((_) async {});

      var tokenReadCount = 0;
      when(() => storage.getAccessToken()).thenAnswer((_) async {
        tokenReadCount++;
        return tokenReadCount == 1 ? 'old-access' : 'new-access';
      });

      var refreshCount = 0;
      final refreshAdapter = _TestAdapter((options) async {
        if (options.path == '/auth/refresh') {
          refreshCount++;
          return _jsonResponse(200, {
            'access_token': 'new-access',
            'refresh_token': 'new-refresh',
          });
        }
        return _jsonResponse(200, {'replayed': true});
      });
      final refreshDio = Dio()..httpClientAdapter = refreshAdapter;
      final cb = _refreshCallbacks(refreshDio);

      final interceptor = AuthInterceptor(
        tokenStorage: storage,
        onAuthFailure: () async {},
        onRefresh: cb.onRefresh,
        replay: cb.replay,
      );

      final dio = Dio()
        ..httpClientAdapter = _TestAdapter((options) async {
          return _jsonResponse(401, {'error': 'expired'});
        })
        ..interceptors.add(interceptor);

      final response = await dio.get<dynamic>('/notes');

      expect(refreshCount, 1);
      expect(response.statusCode, 200);
      verify(() => storage.saveTokens(
            accessToken: 'new-access',
            refreshToken: 'new-refresh',
            userId: 'user-1',
          )).called(1);
    });

    test(
        'on 401 with a failed refresh, invokes onAuthFailure and propagates '
        'the original error', () async {
      final storage = _MockAuthLocalStorage();
      when(() => storage.getAccessToken()).thenAnswer((_) async => 'old');
      when(() => storage.getRefreshToken())
          .thenAnswer((_) async => 'old-refresh');

      var failureCalls = 0;
      final refreshAdapter = _TestAdapter((options) async {
        if (options.path == '/auth/refresh') {
          return _jsonResponse(401, {'error': 'refresh expired'});
        }
        return _jsonResponse(500, {'error': 'unexpected'});
      });
      final refreshDio = Dio()..httpClientAdapter = refreshAdapter;
      final cb = _refreshCallbacks(refreshDio);

      final interceptor = AuthInterceptor(
        tokenStorage: storage,
        onAuthFailure: () async {
          failureCalls++;
        },
        onRefresh: cb.onRefresh,
        replay: cb.replay,
      );

      final dio = Dio()
        ..httpClientAdapter = _TestAdapter((options) async {
          return _jsonResponse(401, {'error': 'expired'});
        })
        ..interceptors.add(interceptor);

      await expectLater(
        () => dio.get<dynamic>('/notes'),
        throwsA(isA<DioException>()),
      );
      expect(failureCalls, 1);
    });

    test(
        'a request marked as already retried (extra.retry = true) is passed '
        'through unchanged', () async {
      final storage = _MockAuthLocalStorage();
      when(() => storage.getAccessToken()).thenAnswer((_) async => 'tok');
      final interceptor = AuthInterceptor(
        tokenStorage: storage,
        onAuthFailure: () async {},
        onRefresh: (_) async {
          fail('refresh should not be called on a retried request');
        },
        replay: (_) {
          fail('replay should not be called on a retried request');
        },
      );

      final dio = Dio()
        ..httpClientAdapter = _TestAdapter((options) async {
          return _jsonResponse(401, {'error': 'still bad'});
        })
        ..interceptors.add(interceptor);

      final err = _dioError(status: 401, path: '/notes', method: 'GET');
      err.requestOptions.extra['retry'] = true;

      await expectLater(
        () => dio.fetch<dynamic>(err.requestOptions),
        throwsA(isA<DioException>()),
      );
    });

    test(
        'concurrent 401s share a single refresh and a single onAuthFailure '
        'call when the refresh fails', () async {
      final storage = _MockAuthLocalStorage();
      when(() => storage.getAccessToken()).thenAnswer((_) async => 'old');
      when(() => storage.getRefreshToken())
          .thenAnswer((_) async => 'old-refresh');

      var refreshHits = 0;
      var failureCalls = 0;
      final refreshAdapter = _TestAdapter((options) async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        if (options.path == '/auth/refresh') {
          refreshHits++;
          return _jsonResponse(401, {'error': 'nope'});
        }
        return _jsonResponse(200, {'x': true});
      });
      final refreshDio = Dio()..httpClientAdapter = refreshAdapter;
      final cb = _refreshCallbacks(refreshDio);

      final interceptor = AuthInterceptor(
        tokenStorage: storage,
        onAuthFailure: () async {
          failureCalls++;
        },
        onRefresh: cb.onRefresh,
        replay: cb.replay,
      );

      final dio = Dio()
        ..httpClientAdapter = _TestAdapter((options) async {
          return _jsonResponse(401, {'error': 'expired'});
        })
        ..interceptors.add(interceptor);

      final futures = <Future<dynamic>>[
        for (final path in ['/a', '/b', '/c'])
          dio.get<dynamic>(path).then<dynamic>(
            (r) => r,
            onError: (Object e, StackTrace s) => e,
          ),
      ];
      final results = await Future.wait<dynamic>(futures);
      for (final r in results) {
        expect(r, isA<DioException>());
      }
      expect(refreshHits, 1);
      expect(failureCalls, 1);
    });
  });

  group('AuthInterceptor.onError (non-401)', () {
    test('non-401 errors are passed through with no refresh attempt', () async {
      final storage = _MockAuthLocalStorage();
      when(() => storage.getAccessToken()).thenAnswer((_) async => 'tok');
      final interceptor = AuthInterceptor(
        tokenStorage: storage,
        onAuthFailure: () async {},
        onRefresh: (_) async {
          fail('refresh should not be called on a 500');
        },
        replay: (_) {
          fail('replay should not be called on a 500');
        },
      );

      final dio = Dio()
        ..httpClientAdapter = _TestAdapter((_) async {
          return _jsonResponse(500, {'error': 'boom'});
        })
        ..interceptors.add(interceptor);

      await expectLater(
        () => dio.get<dynamic>('/notes'),
        throwsA(isA<DioException>()),
      );
    });
  });

  group('AuthInterceptor.onError (401 on auth route)', () {
    test('auth route 401s skip refresh and are passed through', () async {
      final storage = _MockAuthLocalStorage();
      when(() => storage.getAccessToken()).thenAnswer((_) async => 'tok');
      final interceptor = AuthInterceptor(
        tokenStorage: storage,
        onAuthFailure: () async {
          fail('onAuthFailure should not be called for auth-route 401s');
        },
        onRefresh: (_) async {
          fail('refresh should not be called for auth-route 401s');
        },
        replay: (_) {
          fail('replay should not be called for auth-route 401s');
        },
      );

      final dio = Dio()
        ..httpClientAdapter = _TestAdapter((_) async {
          return _jsonResponse(401, {'error': 'invalid credentials'});
        })
        ..interceptors.add(interceptor);

      await expectLater(
        () => dio.post<dynamic>('/api/v1/auth/login', data: {
          'email': 'a@b.com',
          'password': 'x',
        }),
        throwsA(isA<DioException>()),
      );
    });
  });
}
