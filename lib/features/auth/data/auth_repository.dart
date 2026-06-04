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

class AuthRepository {
  AuthRepository({
    required ApiClient apiClient,
    required AuthLocalStorage storage,
  })  : _dio = apiClient.dio,
        _storage = storage;

  final Dio _dio;
  final AuthLocalStorage _storage;

  /// `POST /auth/register` → persist tokens, return the [AuthResult].
  Future<AuthResult> register({
    required String email,
    required String password,
    required String name,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
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
      await _storage.saveTokens(
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
        userId: result.user.id,
      );
      return result;
    } on DioException catch (e) {
      throw fromDioError(e);
    }
  }

  /// `POST /auth/login` → persist tokens, return the [AuthResult].
  Future<AuthResult> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
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
      await _storage.saveTokens(
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
        userId: result.user.id,
      );
      return result;
    } on DioException catch (e) {
      throw fromDioError(e);
    }
  }

  /// `POST /auth/logout` → wipe local tokens.
  ///
  /// Best-effort: if the network call fails the local tokens are still
  /// cleared so the user is signed out from the device's perspective.
  Future<void> logout() async {
    final refreshToken = await _storage.getRefreshToken();
    try {
      if (refreshToken != null) {
        await _dio.post<dynamic>(
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
  Future<bool> isAuthenticated() async {
    final token = await _storage.getAccessToken();
    return token != null && token.isNotEmpty;
  }
}
