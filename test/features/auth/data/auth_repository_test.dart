import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supanotes/core/api/api_client.dart';
import 'package:supanotes/core/api/api_exceptions.dart';
import 'package:supanotes/core/api/auth_interceptor.dart';
import 'package:supanotes/features/auth/data/auth_local_storage.dart';
import 'package:supanotes/features/auth/data/auth_repository.dart';

class _MockAuthLocalStorage extends Mock implements AuthLocalStorage {}

class _AdapterHit {
  _AdapterHit(this.method, this.path, this.body);
  final String method;
  final String path;
  final String body;
}

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.responder);

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
    hits.add(_AdapterHit(options.method, options.path, body));
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

ApiClient _apiClient(_StubAdapter adapter) {
  // We pass a no-op interceptor — this test exercises the repository, not
  // the auth flow. The interceptor must still be present because the
  // ApiClient constructor requires it.
  final interceptor = AuthInterceptor(
    tokenStorage: _NoopStorage(),
    onAuthFailure: () async {},
    onRefresh: (_) async => null,
    replay: (_) => throw UnimplementedError('not used in repository test'),
  );
  final dio = Dio()
    ..httpClientAdapter = adapter
    ..interceptors.add(interceptor);
  return ApiClient(authInterceptor: interceptor, dio: dio);
}

class _NoopStorage implements AuthLocalStorage {
  @override
  Future<void> clear() async {}
  @override
  Future<String?> getAccessToken() async => null;
  @override
  Future<String?> getRefreshToken() async => null;
  @override
  Future<String?> getUserId() async => null;
  @override
  Future<String?> getUserEmail() async => null;
  @override
  Future<String?> getUserName() async => null;
  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
    required String userId,
  }) async {}
  @override
  Future<void> saveUserProfile({
    required String email,
    required String name,
  }) async {}
  @override
  Future<Map<String, dynamic>> getSessionData() async => const {};
  @override
  Future<void> saveSessionData(Map<String, dynamic> data) async {}
}

void main() {
  setUpAll(() {
    registerFallbackValue(
      RequestOptions(path: '/', method: 'GET'),
    );
  });

  group('AuthRepository.register', () {
    test('sends a POST to /auth/register and persists tokens', () async {
      final storage = _MockAuthLocalStorage();
      when(() => storage.saveTokens(
            accessToken: any(named: 'accessToken'),
            refreshToken: any(named: 'refreshToken'),
            userId: any(named: 'userId'),
          )).thenAnswer((_) async {});
      when(() => storage.saveUserProfile(
            email: any(named: 'email'),
            name: any(named: 'name'),
          )).thenAnswer((_) async {});

      late _StubAdapter adapter;
      adapter = _StubAdapter((options) async {
        expect(options.method, 'POST');
        expect(options.path, '/auth/register');
        final body = jsonDecode(adapter.hits.last.body) as Map<String, dynamic>;
        expect(body, {
          'email': 'a@b.com',
          'password': 'hunter2hunter2',
          'name': 'Alice',
        });
        return _jsonResponse(201, {
          'user': {'id': 'u-1', 'email': 'a@b.com', 'name': 'Alice'},
          'access_token': 'access-1',
          'refresh_token': 'refresh-1',
        });
      });

      final repo = AuthRepository(
        apiClient: _apiClient(adapter),
        storage: storage,
      );

      final result = await repo.register(
        email: 'a@b.com',
        password: 'hunter2hunter2',
        name: 'Alice',
      );

      expect(result.user.id, 'u-1');
      expect(result.accessToken, 'access-1');
      expect(result.refreshToken, 'refresh-1');
      verify(() => storage.saveTokens(
            accessToken: 'access-1',
            refreshToken: 'refresh-1',
            userId: 'u-1',
          )).called(1);
      verify(() => storage.saveUserProfile(
            email: 'a@b.com',
            name: 'Alice',
          )).called(1);
    });

    test('translates a 409 into ConflictException', () async {
      final storage = _MockAuthLocalStorage();
      final adapter = _StubAdapter((_) async {
        return _jsonResponse(409, {'error': 'email already in use'});
      });
      final repo = AuthRepository(
        apiClient: _apiClient(adapter),
        storage: storage,
      );

      await expectLater(
        () => repo.register(
          email: 'a@b.com',
          password: 'hunter2hunter2',
          name: 'Alice',
        ),
        throwsA(isA<ConflictException>()),
      );
      verifyNever(() => storage.saveTokens(
            accessToken: any(named: 'accessToken'),
            refreshToken: any(named: 'refreshToken'),
            userId: any(named: 'userId'),
          ));
      verifyNever(() => storage.saveUserProfile(
            email: any(named: 'email'),
            name: any(named: 'name'),
          ));
    });
  });

  group('AuthRepository.login', () {
    test('sends a POST to /auth/login and persists tokens', () async {
      final storage = _MockAuthLocalStorage();
      when(() => storage.saveTokens(
            accessToken: any(named: 'accessToken'),
            refreshToken: any(named: 'refreshToken'),
            userId: any(named: 'userId'),
          )).thenAnswer((_) async {});
      when(() => storage.saveUserProfile(
            email: any(named: 'email'),
            name: any(named: 'name'),
          )).thenAnswer((_) async {});

      final adapter = _StubAdapter((options) async {
        expect(options.path, '/auth/login');
        return _jsonResponse(200, {
          'user': {'id': 'u-2', 'email': 'b@c.com', 'name': 'Bob'},
          'access_token': 'access-2',
          'refresh_token': 'refresh-2',
        });
      });

      final repo = AuthRepository(
        apiClient: _apiClient(adapter),
        storage: storage,
      );

      final result = await repo.login(
        email: 'b@c.com',
        password: 'hunter2hunter2',
      );

      expect(result.user.email, 'b@c.com');
      verify(() => storage.saveTokens(
            accessToken: 'access-2',
            refreshToken: 'refresh-2',
            userId: 'u-2',
          )).called(1);
      verify(() => storage.saveUserProfile(
            email: 'b@c.com',
            name: 'Bob',
          )).called(1);
    });

    test('translates a 401 into UnauthorizedException', () async {
      final storage = _MockAuthLocalStorage();
      final adapter = _StubAdapter((_) async {
        return _jsonResponse(401, {'error': 'invalid credentials'});
      });
      final repo = AuthRepository(
        apiClient: _apiClient(adapter),
        storage: storage,
      );

      await expectLater(
        () => repo.login(email: 'a@b.com', password: 'x'),
        throwsA(isA<UnauthorizedException>()),
      );
    });
  });

  group('AuthRepository.logout', () {
    test('calls /auth/logout with the refresh token and clears storage',
        () async {
      final storage = _MockAuthLocalStorage();
      when(() => storage.getRefreshToken()).thenAnswer((_) async => 'r-1');
      when(() => storage.clear()).thenAnswer((_) async {});

      final adapter = _StubAdapter((options) async {
        expect(options.path, '/auth/logout');
        return _jsonResponse(204, <String, dynamic>{});
      });

      final repo = AuthRepository(
        apiClient: _apiClient(adapter),
        storage: storage,
      );

      await repo.logout();
      expect(adapter.hits.length, 1);
      verify(() => storage.clear()).called(1);
    });

    test('still clears storage when /auth/logout fails', () async {
      final storage = _MockAuthLocalStorage();
      when(() => storage.getRefreshToken()).thenAnswer((_) async => 'r-1');
      when(() => storage.clear()).thenAnswer((_) async {});

      final adapter = _StubAdapter((_) async {
        return _jsonResponse(500, {'error': 'server down'});
      });

      final repo = AuthRepository(
        apiClient: _apiClient(adapter),
        storage: storage,
      );

      await repo.logout();
      verify(() => storage.clear()).called(1);
    });

    test('skips the HTTP call when there is no refresh token', () async {
      final storage = _MockAuthLocalStorage();
      when(() => storage.getRefreshToken()).thenAnswer((_) async => null);
      when(() => storage.clear()).thenAnswer((_) async {});

      final adapter = _StubAdapter((_) async {
        fail('should not reach the backend without a refresh token');
      });

      final repo = AuthRepository(
        apiClient: _apiClient(adapter),
        storage: storage,
      );

      await repo.logout();
      expect(adapter.hits, isEmpty);
      verify(() => storage.clear()).called(1);
    });
  });

  group('AuthRepository.isAuthenticated', () {
    test('returns true when an access token is present', () async {
      final storage = _MockAuthLocalStorage();
      when(() => storage.getAccessToken()).thenAnswer((_) async => 'tok');
      final repo = AuthRepository(
        apiClient: _apiClient(_StubAdapter((_) async => _jsonResponse(200, {}))),
        storage: storage,
      );
      expect(await repo.isAuthenticated(), isTrue);
    });

    test('returns false when no access token is stored', () async {
      final storage = _MockAuthLocalStorage();
      when(() => storage.getAccessToken()).thenAnswer((_) async => null);
      final repo = AuthRepository(
        apiClient: _apiClient(_StubAdapter((_) async => _jsonResponse(200, {}))),
        storage: storage,
      );
      expect(await repo.isAuthenticated(), isFalse);
    });

    test('returns false when the stored access token is empty', () async {
      final storage = _MockAuthLocalStorage();
      when(() => storage.getAccessToken()).thenAnswer((_) async => '');
      final repo = AuthRepository(
        apiClient: _apiClient(_StubAdapter((_) async => _jsonResponse(200, {}))),
        storage: storage,
      );
      expect(await repo.isAuthenticated(), isFalse);
    });
  });
}
