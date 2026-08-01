/// Dio interceptor that injects the bearer token and transparently
/// refreshes it on 401 responses.
///
/// **Request flow** — for every outgoing request, the interceptor attaches
/// `Authorization: Bearer <accessToken>` if a token is present.
///
/// **Error flow** — when a request comes back with HTTP 401 (and the path
/// is not an auth endpoint like /login or /register), the interceptor:
///   1. Calls [_onRefresh] with the current refresh token.
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

/// Signature of the callback invoked when a token refresh has failed and
/// the user must be considered signed out.
typedef AuthFailureHandler = Future<void> Function();

/// Signature for the refresh HTTP call. Receives the plain refresh token
/// and returns a new token pair, or null on failure.
typedef RefreshHandler = Future<AuthTokenPair?> Function(String refreshToken);

typedef AuthTokenPair = ({String accessToken, String refreshToken});

/// Runs a refresh as one session-owned operation, including persistence of
/// the resulting pair. This prevents logout or expiry cleanup from being
/// overtaken by a late refresh response.
typedef RefreshSessionHandler =
    Future<AuthTokenPair?> Function(RefreshHandler refresh);

/// Signature for replaying a failed request after a successful refresh.
typedef ReplayHandler =
    Future<Response<dynamic>> Function(RequestOptions options);

class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required Future<String?> Function() getAccessToken,
    Future<String?> Function()? getRefreshToken,
    Future<void> Function({
      required String accessToken,
      required String refreshToken,
    })?
    saveTokens,
    required this.onAuthFailure,
    required RefreshHandler onRefresh,
    RefreshSessionHandler? refreshSession,
    required ReplayHandler replay,
  }) : _getAccessToken = getAccessToken,
       _getRefreshToken = getRefreshToken,
       _saveTokens = saveTokens,
       _onRefresh = onRefresh,
       _refreshSession = refreshSession,
       _replay = replay;

  final Future<String?> Function() _getAccessToken;
  final Future<String?> Function()? _getRefreshToken;
  final Future<void> Function({
    required String accessToken,
    required String refreshToken,
  })?
  _saveTokens;
  final AuthFailureHandler onAuthFailure;
  final RefreshHandler _onRefresh;
  final RefreshSessionHandler? _refreshSession;
  final ReplayHandler _replay;

  Future<AuthTokenPair?>? _refreshing;
  Future<void>? _notifyingFailure;
  String? _latestAccessToken;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = _latestAccessToken ?? await _getAccessToken();
    if (token != null) {
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

    late final AuthTokenPair? refreshedTokens;
    try {
      refreshedTokens = await _refreshOnce();
    } on DioException {
      // A temporary refresh outage must not destroy a valid local session.
      handler.next(err);
      return;
    }
    if (refreshedTokens == null) {
      await _notifyFailureOnce();
      handler.next(err);
      return;
    }

    err.requestOptions.headers['Authorization'] =
        'Bearer ${refreshedTokens.accessToken}';
    err.requestOptions.extra['retry'] = true;

    try {
      final response = await _replay(err.requestOptions);
      handler.resolve(response);
    } on DioException catch (e) {
      handler.next(e);
    }
  }

  Future<AuthTokenPair?> _refreshOnce() {
    final cached = _refreshing;
    if (cached != null) return cached;
    late Future<AuthTokenPair?> future;
    future = _doRefresh().whenComplete(() {
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

  Future<AuthTokenPair?> _doRefresh() async {
    final refreshSession = _refreshSession;
    if (refreshSession != null) {
      return refreshSession(_onRefresh);
    }

    final getRefreshToken = _getRefreshToken;
    final saveTokens = _saveTokens;
    if (getRefreshToken == null || saveTokens == null) {
      throw StateError('AuthInterceptor requires refreshSession');
    }
    final refreshToken = await getRefreshToken();
    if (refreshToken == null) return null;

    final tokens = await _onRefresh(refreshToken);
    if (tokens == null) return null;

    await saveTokens(
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
    );
    _latestAccessToken = tokens.accessToken;
    return tokens;
  }
}

bool _isUnauthenticatedAuthRoute(String path) {
  return switch (path) {
    '/auth/login' ||
    '/auth/register' ||
    '/auth/refresh' ||
    '/auth/logout' => true,
    _ => false,
  };
}
