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

import 'package:supanotes/features/auth/data/auth_local_storage.dart';

/// Signature of the callback invoked when a token refresh has failed and
/// the user must be considered signed out.
typedef AuthFailureHandler = Future<void> Function();

/// Signature for the refresh HTTP call. Receives the plain refresh token
/// and returns a new token pair, or null on failure.
typedef RefreshHandler = Future<({String accessToken, String refreshToken})?> Function(
  String refreshToken,
);

/// Signature for replaying a failed request after a successful refresh.
typedef ReplayHandler = Future<Response<dynamic>> Function(RequestOptions options);

class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required this.tokenStorage,
    required this.onAuthFailure,
    required RefreshHandler onRefresh,
    required ReplayHandler replay,
  })  : _onRefresh = onRefresh,
        _replay = replay;

  final AuthLocalStorage tokenStorage;
  final AuthFailureHandler onAuthFailure;
  final RefreshHandler _onRefresh;
  final ReplayHandler _replay;

  Future<bool>? _refreshing;
  Future<void>? _notifyingFailure;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await tokenStorage.getAccessToken();
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

    // Skip auth endpoints (login/register) so failed credentials
    // don't trigger an unnecessary session-clear cycle.
    if (err.requestOptions.path.startsWith('/api/v1/auth/')) {
      handler.next(err);
      return;
    }

    final refreshed = await _refreshOnce();
    if (!refreshed) {
      await _notifyFailureOnce();
      handler.next(err);
      return;
    }

    final newToken = await tokenStorage.getAccessToken();
    if (newToken == null) {
      await _notifyFailureOnce();
      handler.next(err);
      return;
    }

    err.requestOptions.headers['Authorization'] = 'Bearer $newToken';
    err.requestOptions.extra['retry'] = true;

    try {
      final response = await _replay(err.requestOptions);
      handler.resolve(response);
    } on DioException catch (e) {
      handler.next(e);
    }
  }

  Future<bool> _refreshOnce() {
    final cached = _refreshing;
    if (cached != null) return cached;
    late Future<bool> future;
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

  Future<bool> _doRefresh() async {
    final refreshToken = await tokenStorage.getRefreshToken();
    if (refreshToken == null) return false;

    final tokens = await _onRefresh(refreshToken);
    if (tokens == null) return false;

    final userId = await tokenStorage.getUserId();
    await tokenStorage.saveTokens(
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
      userId: userId ?? '',
    );
    return true;
  }
}
