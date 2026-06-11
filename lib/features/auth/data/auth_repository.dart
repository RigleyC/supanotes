/// Auth-related HTTP calls.
///
/// Each public method is a thin wrapper around a single endpoint that:
///   1. Issues the HTTP call via [ApiClient.dio].
///   2. Translates a [DioException] into the typed [ApiException] hierarchy
///      so callers can `try`/`catch` against a single failure type.
///   3. Persists the JWT pair via [AuthLocalStorage] on success.
///
/// The repository does **not** know about Riverpod or widget state — the
/// [AuthController] is responsible for translating these results into
/// application state.
library;

import 'package:dio/dio.dart';

import 'package:supanotes/core/api/api_client.dart';
import 'package:supanotes/core/api/api_exceptions.dart';
import 'package:supanotes/features/auth/data/auth_local_storage.dart';
import 'package:supanotes/features/auth/domain/user.dart';

abstract class IAuthRepository {
  Future<AuthResult> register({required String email, required String password, required String name});
  Future<AuthResult> login({required String email, required String password});
  Future<void> logout();
  Future<bool> isAuthenticated();
  Future<void> registerDeviceToken(String token);
}

class AuthRepository implements IAuthRepository {
  AuthRepository({
    required ApiClient apiClient,
    required AuthLocalStorage storage,
  })  : _api = apiClient,
        _storage = storage;

  final ApiClient _api;
  final AuthLocalStorage _storage;

  /// `POST /auth/register` → persist tokens, return the [AuthResult].
  @override
  Future<AuthResult> register({
    required String email,
    required String password,
    required String name,
  }) async {
    try {
      final response = await _api.post<Map<String, dynamic>>(
        '/auth/register',
        data: {
          'email': email,
          'password': password,
          'name': name,
        },
      );
      final body = response.data;
      if (body == null) {
        throw const ServerException(
          message: 'Empty response from server',
          statusCode: 500,
        );
      }
      final result = AuthResult.fromJson(body);
      await _storage.saveUser(user: result.user);
      await _storage.saveTokens(
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
      );
      await _storage.saveSessionData({
        'settings': result.session.settings,
        'soul': result.session.soul,
        'contexts': result.session.contexts,
        'routines': result.session.routines,
      });
      return result;
    } on DioException catch (e) {
      throw fromDioError(e);
    }
  }

  /// `POST /auth/login` → persist tokens, return the [AuthResult].
  @override
  Future<AuthResult> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _api.post<Map<String, dynamic>>(
        '/auth/login',
        data: {
          'email': email,
          'password': password,
        },
      );
      final body = response.data;
      if (body == null) {
        throw const ServerException(
          message: 'Empty response from server',
          statusCode: 500,
        );
      }
      final result = AuthResult.fromJson(body);
      await _storage.saveUser(user: result.user);
      await _storage.saveTokens(
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
      );
      await _storage.saveSessionData({
        'settings': result.session.settings,
        'soul': result.session.soul,
        'contexts': result.session.contexts,
        'routines': result.session.routines,
      });
      return result;
    } on DioException catch (e) {
      throw fromDioError(e);
    }
  }

  /// `POST /auth/logout` → wipe local tokens.
  ///
  /// Best-effort: if the network call fails the local tokens are still
  /// cleared so the user is signed out from the device's perspective.
  @override
  Future<void> logout() async {
    final refreshToken = await _storage.getRefreshToken();
    try {
      if (refreshToken != null) {
        await _api.post<dynamic>(
          '/auth/logout',
          data: {'refresh_token': refreshToken},
        );
      }
    } on DioException {
      // Swallow: we are logging out anyway.
    } finally {
      await _storage.clear();
    }
  }

  /// Whether the device currently holds a (possibly stale) access token.
  ///
  /// This is the answer to "do we have a session on disk?" — it does not
  /// tell you whether the backend still accepts the token. Use the
  /// [AuthInterceptor] for that: any 401 on a real call will surface as a
  /// refresh attempt, and a failed refresh will clear the tokens.
  @override
  Future<bool> isAuthenticated() async {
    final token = await _storage.getAccessToken();
    return token != null && token.isNotEmpty;
  }

  /// Registers the device's FCM push token with the backend.
  @override
  Future<void> registerDeviceToken(String token) async {
    try {
      await _api.post('/api/v1/device-tokens', data: {'token': token});
    } on DioException {
      // Non-fatal — push will simply not work until the next registration.
    }
  }
}
