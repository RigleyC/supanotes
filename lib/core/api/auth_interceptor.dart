/// Dio interceptor that injects the bearer token and transparently
/// refreshes it on 401 responses.
///
/// **Request flow** — for every outgoing request, the interceptor attaches
/// `Authorization: Bearer <accessToken>` if a token is present.
///
/// **Error flow** — when a request comes back with HTTP 401 (and the path
/// is not an auth endpoint like /login or /register), the interceptor:
///   1. Runs the session-owned refresh operation.
///   2. If the refresh succeeds, persists the new pair and replays the
///      original request via [_replay].
///   3. If the refresh fails, invokes [onAuthFailure] once and propagates
///      the original 401 error.
///
/// **Single-flight refresh** — concurrent 401s share a single in-flight
/// refresh future via [_refreshing], and a single in-flight auth-failure
/// notification via [_notifyingFailure]. This avoids the thundering-herd
/// of duplicate refresh calls when many requests share an expired token.
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:supanotes/core/auth/auth_tokens.dart' as auth;

export 'package:supanotes/core/auth/auth_tokens.dart'
    show
        AuthTokenPair,
        RefreshHandler,
        RefreshSessionHandler,
        SessionRefreshHandler;

/// Signature of the callback invoked when a token refresh has failed and
/// the user must be considered signed out.
typedef AuthFailureHandler = Future<void> Function();

/// Signature for replaying a failed request after a successful refresh.
typedef ReplayHandler =
    Future<Response<dynamic>> Function(RequestOptions options);

class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required Future<String?> Function() getAccessToken,
    required this.onAuthFailure,
    required auth.SessionRefreshHandler refreshSession,
    required ReplayHandler replay,
  }) : _getAccessToken = getAccessToken,
       _refreshSession = refreshSession,
       _replay = replay;

  final Future<String?> Function() _getAccessToken;
  final AuthFailureHandler onAuthFailure;
  final auth.SessionRefreshHandler _refreshSession;
  final ReplayHandler _replay;

  Future<auth.AuthTokenPair?>? _refreshing;
  Future<void>? _notifyingFailure;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await _getAccessToken();
    if (_hasValue(token)) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final isUnauthorized = err.response?.statusCode == 401;
    final isAlreadyRetried = err.requestOptions.extra['retry'] == true;
    if (!isUnauthorized || isAlreadyRetried) {
      handler.next(err);
      return;
    }

    // Skip endpoints that do not require an authenticated session. Other
    // auth endpoints, such as MCP token generation, still need refresh and
    // replay when the access token expires.
    if (_isUnauthenticatedAuthRoute(err.requestOptions.path)) {
      handler.next(err);
      return;
    }

    final failedAccessToken = _requestAccessToken(err.requestOptions);
    try {
      final currentAccessToken = await _getAccessToken();
      if (_isNewerAccessToken(currentAccessToken, failedAccessToken)) {
        await _replayWithToken(err, currentAccessToken, handler);
        return;
      }

      final refreshedTokens = await _refreshOnce();
      if (refreshedTokens == null) {
        // A refresh may have completed, or a new login may have installed a
        // session, between the first token read and the refresh result.
        final currentTokenAfterRefresh = await _getAccessToken();
        if (_isNewerAccessToken(
          currentTokenAfterRefresh,
          failedAccessToken,
        )) {
          await _replayWithToken(err, currentTokenAfterRefresh, handler);
          return;
        }
        try {
          await _notifyFailureOnce();
        } finally {
          handler.next(err);
        }
        return;
      }

      await _replayWithToken(err, refreshedTokens.accessToken, handler);
    } on DioException {
      // A temporary refresh outage must not destroy a valid local session.
      handler.next(err);
      return;
    } on Object {
      // Persistence/platform failures are not proof that the server rejected
      // the session. Keep the original error and let the session survive.
      handler.next(err);
      return;
    }
  }

  Future<auth.AuthTokenPair?> _refreshOnce() {
    final cached = _refreshing;
    if (cached != null) return cached;
    late Future<auth.AuthTokenPair?> future;
    future = _refreshSession().whenComplete(() {
      if (identical(_refreshing, future)) {
        _refreshing = null;
      }
    });
    _refreshing = future;
    return future;
  }

  Future<void> _notifyFailureOnce() {
    final cached = _notifyingFailure;
    if (cached != null) return cached;
    late Future<void> future;
    future = onAuthFailure().whenComplete(() {
      if (identical(_notifyingFailure, future)) {
        _notifyingFailure = null;
      }
    });
    _notifyingFailure = future;
    return future;
  }

  Future<void> _replayWithToken(
    DioException error,
    String? accessToken,
    ErrorInterceptorHandler handler,
  ) async {
    if (accessToken == null || accessToken.isEmpty) {
      handler.next(error);
      return;
    }

    error.requestOptions.headers['Authorization'] = 'Bearer $accessToken';
    error.requestOptions.extra['retry'] = true;

    try {
      final response = await _replay(error.requestOptions);
      handler.resolve(response);
    } on DioException catch (replayError) {
      handler.next(replayError);
    }
  }
}

String? _requestAccessToken(RequestOptions options) {
  final authorization = options.headers['Authorization'];
  if (authorization is! String || !authorization.startsWith('Bearer ')) {
    return null;
  }
  return authorization.substring('Bearer '.length);
}

bool _isNewerAccessToken(String? current, String? failed) {
  return _hasValue(current) && _hasValue(failed) && current != failed;
}

bool _hasValue(String? value) => value != null && value.isNotEmpty;

bool _isUnauthenticatedAuthRoute(String path) {
  return switch (path) {
    '/auth/login' ||
    '/auth/register' ||
    '/auth/refresh' ||
    '/auth/logout' => true,
    _ => false,
  };
}
