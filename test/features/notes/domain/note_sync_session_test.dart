import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/notes/data/note_sync_client.dart';
import 'package:supanotes/features/notes/domain/note_sync_session.dart';

void main() {
  group('NoteSyncSession error classification', () {
    test(
      'isProtocolError identifies 4xx HTTP responses and format/protocol errors',
      () {
        final reqOptions = RequestOptions(path: '/');

        final err401 = DioException(
          requestOptions: reqOptions,
          response: Response(requestOptions: reqOptions, statusCode: 401),
        );
        final err403 = DioException(
          requestOptions: reqOptions,
          response: Response(requestOptions: reqOptions, statusCode: 403),
        );
        final err400 = DioException(
          requestOptions: reqOptions,
          response: Response(requestOptions: reqOptions, statusCode: 400),
        );
        final stateErr = StateError('protocol conflict');
        final noteOpsErr = NoteOperationsException(
          errorCode: 'INVALID',
          message: 'invalid',
        );
        final noteOps403 = NoteOperationsException(
          errorCode: 'FORBIDDEN',
          message: 'forbidden',
          statusCode: 403,
        );

        expect(NoteSyncSession.isProtocolError(err401), isTrue);
        expect(NoteSyncSession.isProtocolError(err403), isTrue);
        expect(NoteSyncSession.isProtocolError(err400), isTrue);
        expect(NoteSyncSession.isProtocolError(stateErr), isTrue);
        expect(NoteSyncSession.isProtocolError(noteOpsErr), isTrue);
        expect(NoteSyncSession.isProtocolError(noteOps403), isTrue);
      },
    );

    test(
      'isProtocolError identifies network timeouts and 5xx errors as transient',
      () {
        final reqOptions = RequestOptions(path: '/');

        final connTimeout = DioException(
          requestOptions: reqOptions,
          type: DioExceptionType.connectionTimeout,
        );
        final connErr = DioException(
          requestOptions: reqOptions,
          type: DioExceptionType.connectionError,
        );
        final err500 = DioException(
          requestOptions: reqOptions,
          response: Response(requestOptions: reqOptions, statusCode: 500),
        );
        final err503 = DioException(
          requestOptions: reqOptions,
          response: Response(requestOptions: reqOptions, statusCode: 503),
        );
        final noteOpsNetwork = NoteOperationsException(
          errorCode: 'NETWORK_ERROR',
          message: 'offline',
        );
        final noteOps500 = NoteOperationsException(
          errorCode: 'INTERNAL',
          message: 'server failed',
          statusCode: 500,
        );

        expect(NoteSyncSession.isProtocolError(connTimeout), isFalse);
        expect(NoteSyncSession.isProtocolError(connErr), isFalse);
        expect(NoteSyncSession.isProtocolError(err500), isFalse);
        expect(NoteSyncSession.isProtocolError(err503), isFalse);
        expect(NoteSyncSession.isProtocolError(noteOpsNetwork), isFalse);
        expect(NoteSyncSession.isProtocolError(noteOps500), isFalse);
      },
    );
  });
}
