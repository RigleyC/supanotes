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

import 'package:supanotes/core/api/auth_interceptor.dart';
import 'package:supanotes/core/constants/api_constants.dart';

class ApiClient {
  /// The underlying Dio instance.
  ///
  /// Exposed so tests can stub adapters and so advanced callers can plug
  /// in their own interceptors. Application code should normally interact
  /// with the higher-level repositories instead.
  final Dio dio;

  ApiClient({required AuthInterceptor authInterceptor})
      : dio = _build(authInterceptor);

  static Dio _build(AuthInterceptor authInterceptor) {
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

    // Auth must be the first interceptor so the retry path (which replays
    // the original RequestOptions) still goes through it on the way out.
    dio.interceptors.add(authInterceptor);
    dio.interceptors.add(_LogInterceptor());
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
