/// Dio interceptor that injects the bearer token and transparently
/// refreshes it on 401 responses.
///
/// **Request flow** — for every outgoing request whose path is *not* under
/// `/auth/`, the interceptor attaches `Authorization: Bearer <accessToken>`
/// (if a token is present in [tokenStorage]).
///
/// **Error flow** — when a request comes back with HTTP 401, the
/// interceptor:
///   1. Calls `POST /auth/refresh` on a *secondary* [Dio] that does **not**
///      have this interceptor attached, so the refresh call itself cannot
///      recurse.
///   2. If the refresh succeeds, persists the new pair of tokens and
///      replays the original request with the new bearer header.
///   3. If the refresh fails, invokes [onAuthFailure] once (no matter how
///      many concurrent requests are in flight) and propagates the
///      original 401 error.
///
/// **Single-flight refresh** — concurrent 401s share a single in-flight
/// refresh future via [_refreshing], and a single in-flight auth-failure
/// notification via [_notifyingFailure]. This avoids the thundering-herd
/// of duplicate refresh calls when many requests share an expired token.
library;

import 'dart:async';

import 'package:dio/dio.dart';

import 'package:supanotes/core/constants/api_constants.dart';
import 'package:supanotes/features/auth/data/auth_local_storage.dart';

/// Signature of the callback invoked when a token refresh has failed and
/// the user must be considered signed out.
typedef AuthFailureHandler = Future<void> Function();

class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required this.tokenStorage,
    required this.onAuthFailure,
    Dio? refreshDio,
  }) : _refreshDio = refreshDio ?? _defaultRefreshDio();

  final AuthLocalStorage tokenStorage;
  final AuthFailureHandler onAuthFailure;
  final Dio _refreshDio;

  // Single-flight guards. Stored as nullable futures so concurrent 401s
  // can `await` the same in-flight work.
  Future<bool>? _refreshing;
  Future<void>? _notifyingFailure;

  static Dio _defaultRefreshDio() {
    final dio = Dio();
    dio.options
      ..baseUrl = ApiConstants.baseUrl
      ..connectTimeout = const Duration(
        milliseconds: ApiConstants.connectTimeoutMs,
      )
      ..receiveTimeout = const Duration(
        milliseconds: ApiConstants.receiveTimeoutMs,
      )
      ..contentType = Headers.jsonContentType
      ..responseType = ResponseType.json;
    return dio;
  }

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (_isAuthRoute(options.path)) {
      handler.next(options);
      return;
    }
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
      final response = await _refreshDio.fetch<dynamic>(err.requestOptions);
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
      // Only clear if we are still the most recent attempt. A new attempt
      // started by a later 401 should keep its own slot.
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

    try {
      final response = await _refreshDio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refresh_token': refreshToken},
      );
      final data = response.data;
      if (data == null) return false;
      final newAccess = data['access_token'] as String?;
      final newRefresh = data['refresh_token'] as String?;
      if (newAccess == null || newRefresh == null) return false;

      // userId is preserved across refreshes, so we just round-trip it.
      final userId = await tokenStorage.getUserId();
      await tokenStorage.saveTokens(
        accessToken: newAccess,
        refreshToken: newRefresh,
        userId: userId ?? '',
      );
      return true;
    } on DioException {
      return false;
    }
  }

  bool _isAuthRoute(String path) {
    return path.startsWith('/api/v1/auth/');
  }
}
