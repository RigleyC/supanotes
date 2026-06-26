/// HTTP client wrapper around [Dio] used by every feature repository.
///
/// Responsibilities:
///   * Wire the base URL, timeouts and content type from
///     [ApiConstants] so feature code never reads transport config.
///   * Attach the cross-cutting [AuthInterceptor] (JWT injection +
///     automatic refresh on 401).
///   * Optionally log requests in debug builds for easier local dev.
///
/// Feature code should depend on [ApiClient], not on Dio directly, so the
/// interceptor chain and base config can be swapped in tests without
/// touching every call site.
library;

import 'dart:developer' as dev;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'package:supanotes/core/api/auth_interceptor.dart';
import 'package:supanotes/core/constants/api_constants.dart';

class ApiClient {
  final Dio _dio;

  /// Production constructor — builds the [Dio] instance, creates the
  /// [AuthInterceptor] internally, and wires refresh + replay to use the
  /// same [Dio] (the interceptor's own path and retry guards prevent
  /// recursion).
  ApiClient({
    required Future<String?> Function() getAccessToken,
    required Future<String?> Function() getRefreshToken,
    required Future<void> Function({
      required String accessToken,
      required String refreshToken,
    }) saveTokens,
    required AuthFailureHandler onAuthFailure,
  }) : _dio = _buildDio() {
    final interceptor = AuthInterceptor(
      getAccessToken: getAccessToken,
      getRefreshToken: getRefreshToken,
      saveTokens: saveTokens,
      onAuthFailure: onAuthFailure,
      onRefresh: (refreshToken) async {
        try {
          final response = await _dio.post<Map<String, dynamic>>(
            '/auth/refresh',
            data: {'refresh_token': refreshToken},
          );
          final data = response.data;
          if (data == null) return null;
          final newAccess = data['access_token'] as String?;
          final newRefresh = data['refresh_token'] as String?;
          if (newAccess == null || newRefresh == null) return null;
          return (accessToken: newAccess, refreshToken: newRefresh);
        } on DioException {
          return null;
        }
      },
      replay: (options) => _dio.fetch<dynamic>(options),
    );
    _dio.interceptors.add(interceptor);
    _dio.interceptors.add(_LogInterceptor());
  }

  /// Test constructor — accepts a pre-built [AuthInterceptor] and an
  /// optional [Dio] for mocking HTTP responses.
  ApiClient.test({required AuthInterceptor authInterceptor, Dio? dio})
    : _dio = dio ?? _buildDio() {
    _dio.interceptors.add(authInterceptor);
  }

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    return _dio.get<T>(
      path,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
  }

  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    return _dio.post<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
  }

  Future<Response<T>> put<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    return _dio.put<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
  }

  Future<Response<T>> patch<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    return _dio.patch<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
  }

  Future<Response<T>> delete<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    return _dio.delete<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
  }

  Future<Response<ResponseBody>> postStream(
    String path, {
    dynamic data,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    final opts = (options ?? Options()).copyWith(
      responseType: ResponseType.stream,
    );
    return _dio.post<ResponseBody>(
      path,
      data: data,
      options: opts,
      cancelToken: cancelToken,
    );
  }

  static Dio _buildDio() {
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
}

/// Minimal request/response logger.
///
/// In production this is a no-op; we only print when the host asserts
/// `kDebugMode` or when a request fails (so production crashes leave a
/// breadcrumb in `flutter logs`).

class _LogInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (kDebugMode) {
      debugPrint('[ApiClient Error] ${err.toString()}');
      if (err.response?.data != null) {
        debugPrint('[ApiClient Response Data] ${err.response?.data}');
      }
    }
    
    dev.log(
      '[ApiClient] ${err.requestOptions.method} '
      '${err.requestOptions.uri} -> '
      '${err.response?.statusCode ?? "no-response"} '
      '${err.message ?? ""}',
      name: 'ApiClient',
    );
    handler.next(err);
  }
}
