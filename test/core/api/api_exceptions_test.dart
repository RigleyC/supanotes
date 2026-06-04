import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/core/api/api_exceptions.dart';

void main() {
  group('fromDioError', () {
    test('parses { "error": "msg" } from a 400 response', () {
      final err = DioException(
        requestOptions: RequestOptions(path: '/x'),
        response: Response<dynamic>(
          requestOptions: RequestOptions(path: '/x'),
          statusCode: 400,
          data: {'error': 'invalid input'},
        ),
        type: DioExceptionType.badResponse,
      );
      final mapped = fromDioError(err);
      expect(mapped, isA<ApiException>());
      expect(mapped, isNot(isA<UnauthorizedException>()));
      expect(mapped.statusCode, 400);
      expect(mapped.message, 'invalid input');
    });

    test('maps 401 to UnauthorizedException', () {
      final err = DioException(
        requestOptions: RequestOptions(path: '/x'),
        response: Response<dynamic>(
          requestOptions: RequestOptions(path: '/x'),
          statusCode: 401,
          data: {'error': 'expired'},
        ),
        type: DioExceptionType.badResponse,
      );
      final mapped = fromDioError(err);
      expect(mapped, isA<UnauthorizedException>());
      expect(mapped.statusCode, 401);
      expect(mapped.message, 'expired');
    });

    test('falls back to a default message when 401 body has no error field',
        () {
      final err = DioException(
        requestOptions: RequestOptions(path: '/x'),
        response: Response<dynamic>(
          requestOptions: RequestOptions(path: '/x'),
          statusCode: 401,
          data: <String, dynamic>{},
        ),
        type: DioExceptionType.badResponse,
      );
      final mapped = fromDioError(err);
      expect(mapped, isA<UnauthorizedException>());
      expect(mapped.statusCode, 401);
      expect(mapped.message, 'Unauthorized');
    });

    test('maps 409 to ConflictException', () {
      final err = DioException(
        requestOptions: RequestOptions(path: '/x'),
        response: Response<dynamic>(
          requestOptions: RequestOptions(path: '/x'),
          statusCode: 409,
          data: {'error': 'email already exists'},
        ),
        type: DioExceptionType.badResponse,
      );
      final mapped = fromDioError(err);
      expect(mapped, isA<ConflictException>());
      expect(mapped.message, 'email already exists');
    });

    test('maps 5xx to ServerException', () {
      final err = DioException(
        requestOptions: RequestOptions(path: '/x'),
        response: Response<dynamic>(
          requestOptions: RequestOptions(path: '/x'),
          statusCode: 503,
          data: {'error': 'db down'},
        ),
        type: DioExceptionType.badResponse,
      );
      final mapped = fromDioError(err);
      expect(mapped, isA<ServerException>());
      expect(mapped.statusCode, 503);
      expect(mapped.message, 'db down');
    });

    test('connection timeout maps to NetworkException', () {
      final err = DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: DioExceptionType.connectionTimeout,
        message: 'timeout while connecting',
      );
      final mapped = fromDioError(err);
      expect(mapped, isA<NetworkException>());
      expect(mapped.message, 'timeout while connecting');
    });

    test('connection error maps to NetworkException with fallback', () {
      final err = DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: DioExceptionType.connectionError,
      );
      final mapped = fromDioError(err);
      expect(mapped, isA<NetworkException>());
      expect(mapped.message, 'Network unreachable');
    });

    test('non-error data is not interpreted as { error: ... }', () {
      final err = DioException(
        requestOptions: RequestOptions(path: '/x'),
        response: Response<dynamic>(
          requestOptions: RequestOptions(path: '/x'),
          statusCode: 400,
          data: 'plain text',
        ),
        type: DioExceptionType.badResponse,
      );
      final mapped = fromDioError(err);
      expect(mapped, isA<ApiException>());
      expect(mapped, isNot(isA<UnauthorizedException>()));
      expect(mapped.statusCode, 400);
      expect(mapped.message, 'Request failed');
    });
  });
}
