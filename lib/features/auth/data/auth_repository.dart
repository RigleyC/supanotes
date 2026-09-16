import 'package:dio/dio.dart';

import 'package:supanotes/core/api/api_client.dart';
import 'package:supanotes/core/api/api_exceptions.dart';
import 'package:supanotes/core/auth/auth_token_manager.dart';
import 'package:supanotes/features/auth/data/auth_local_storage.dart';
import 'package:supanotes/features/auth/domain/user.dart';

class AuthRepository {
  AuthRepository({
    required ApiClient apiClient,
    required AuthLocalStorage storage,
    required AuthTokenManager tokenManager,
  }) : _api = apiClient,
       _storage = storage,
       _tokenManager = tokenManager;

  final ApiClient _api;
  final AuthLocalStorage _storage;
  final AuthTokenManager _tokenManager;

  Future<AuthResult> register({
    required String email,
    required String password,
    required String name,
  }) {
    return _authenticate(
      '/auth/register',
      data: {'email': email, 'password': password, 'name': name},
    );
  }

  Future<AuthResult> login({
    required String email,
    required String password,
  }) {
    return _authenticate(
      '/auth/login',
      data: {'email': email, 'password': password},
    );
  }

  Future<AuthResult> _authenticate(
    String path, {
    required Map<String, dynamic> data,
  }) async {
    try {
      final response = await _api.post<Map<String, dynamic>>(
        path,
        data: data,
      );
      final body = response.data;
      if (body == null) {
        throw const ServerException(
          message: 'Empty response from server',
          statusCode: 500,
        );
      }

      final result = AuthResult.fromJson(body);
      try {
        await _tokenManager.installSession(
          accessToken: result.accessToken,
          refreshToken: result.refreshToken,
        );
        await _storage.saveUser(user: result.user);
      } catch (error, stackTrace) {
        Object? cleanupError;
        try {
          await _tokenManager.clearSession();
        } on Object catch (cleanupFailure) {
          cleanupError = cleanupFailure;
        }
        Error.throwWithStackTrace(
          AuthSessionInstallationException(error, cleanupError),
          stackTrace,
        );
      }
      return result;
    } on DioException catch (error) {
      throw fromDioError(error);
    }
  }

  Future<void> logout() async {
    await _tokenManager.withSessionLock(_logoutWithRefreshToken);
  }

  Future<void> _logoutWithRefreshToken(String? refreshToken) async {
    try {
      if (refreshToken != null && refreshToken.isNotEmpty) {
        await _api.post<dynamic>(
          '/auth/logout',
          data: {'refresh_token': refreshToken},
        );
      }
    } on DioException {
      // Logout is best effort; the controller owns local cleanup.
    }
  }
}

/// Indicates that a login or registration response could not be installed as
/// a complete local session and the session was cleared.
final class AuthSessionInstallationException implements Exception {
  /// Creates an exception for a failed session installation and cleanup.
  AuthSessionInstallationException(this.cause, this.cleanupError)
    : message =
          'Auth session installation failed: $cause'
          '${cleanupError == null ? '' : '; cleanup: $cleanupError'}';

  /// Error raised while installing the new session.
  final Object cause;

  /// Error raised while clearing the incomplete session, if any.
  final Object? cleanupError;

  /// Human-readable description of the installation and cleanup failures.
  final String message;

  @override
  String toString() => message;
}
