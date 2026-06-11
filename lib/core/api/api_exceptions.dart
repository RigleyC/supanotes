/// Typed exceptions for the HTTP layer.
///
/// The [ApiClient] uses Dio under the hood, but feature code should never
/// see a [DioException] directly — it should catch one of the subclasses
/// declared here so the rest of the app can pattern-match on the failure
/// mode (network down vs. unauthorized vs. server error) without having to
/// know about Dio at all.
library;

import 'package:dio/dio.dart';

/// Base class for every API-related error.
class ApiException implements Exception {
  /// Human-readable description of the failure.
  ///
  /// When the backend returned a JSON body of the form
  /// `{"error": "message"}` this is the value of that field; otherwise it
  /// falls back to [DioException.message] or a generic placeholder.
  final String message;

  /// HTTP status code, if the request reached the server.
  final int? statusCode;

  const ApiException({required this.message, this.statusCode});

  @override
  String toString() {
    final code = statusCode != null ? ' ($statusCode)' : '';
    return 'ApiException$code: $message';
  }
}

/// 401 — access token is missing, expired, or otherwise invalid.
///
/// The caller is expected to attempt a refresh + retry; if that also
/// fails the [AuthInterceptor] escalates to a hard logout.
class UnauthorizedException extends ApiException {
  const UnauthorizedException({required super.message, super.statusCode = 401});
}

/// 404 — the requested resource does not exist.
class NotFoundException extends ApiException {
  const NotFoundException({required super.message, super.statusCode = 404});
}

/// 409 — request could not be completed because of a conflict with the
/// current state of the target resource (e.g. duplicate email on register).
class ConflictException extends ApiException {
  const ConflictException({required super.message, super.statusCode = 409});
}

/// 5xx — server-side failure. The request was syntactically valid but the
/// server could not fulfil it.
class ServerException extends ApiException {
  const ServerException({required super.message, required super.statusCode});
}

/// No usable response was ever received: connection refused, DNS failure,
/// TLS error, request or receive timeout, etc.
class NetworkException extends ApiException {
  const NetworkException({
    required super.message,
    super.statusCode,
  });
}

/// Maps a [DioException] to the most specific [ApiException] subclass.
///
/// The body of the failing response is inspected for a JSON object of the
/// shape `{"error": "..."}` so the surfaced [message] matches the one the
/// backend actually returned, not the generic Dio transport message.
ApiException fromDioError(DioException error) {
  final response = error.response;
  final statusCode = response?.statusCode;
  final parsed = _parseErrorBody(response?.data);

  switch (error.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.connectionError:
      return NetworkException(
        message: parsed ?? _fallbackMessage(error, 'Network unreachable'),
        statusCode: statusCode,
      );
    case DioExceptionType.badCertificate:
      return NetworkException(
        message: parsed ?? _fallbackMessage(error, 'Invalid TLS certificate'),
      );
    case DioExceptionType.cancel:
      return ApiException(
        message: parsed ?? _fallbackMessage(error, 'Request cancelled'),
        statusCode: statusCode,
      );
    case DioExceptionType.badResponse:
    case DioExceptionType.unknown:
      if (statusCode == 401) {
        return UnauthorizedException(
          message: parsed ?? _fallbackMessage(error, 'Unauthorized'),
        );
      }
      if (statusCode == 404) {
        return NotFoundException(
          message: parsed ?? _fallbackMessage(error, 'Not found'),
        );
      }
      if (statusCode == 409) {
        return ConflictException(
          message: parsed ?? _fallbackMessage(error, 'Conflict'),
        );
      }
      if (statusCode != null && statusCode >= 500) {
        return ServerException(
          message: parsed ?? _fallbackMessage(error, 'Server error'),
          statusCode: statusCode,
        );
      }
      if (statusCode != null && statusCode >= 400) {
        return ApiException(
          message: parsed ?? _fallbackMessage(error, 'Request failed'),
          statusCode: statusCode,
        );
      }
      return NetworkException(
        message: parsed ?? _fallbackMessage(error, 'Network error'),
        statusCode: statusCode,
      );
  }
}

String? _parseErrorBody(Object? data) {
  if (data is Map && data['error'] is String) {
    return data['error'] as String;
  }
  return null;
}

String _fallbackMessage(DioException error, String fallback) {
  final message = error.message;
  if (message == null || message.isEmpty) return fallback;
  return message;
}
