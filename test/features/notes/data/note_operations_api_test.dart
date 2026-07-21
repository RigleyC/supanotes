import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:supanotes/core/api/api_client.dart';
import 'package:supanotes/features/notes/data/note_operations_api.dart';

class MockApiClient extends Mock implements ApiClient {}

class MockResponse<T> extends Mock implements Response<T> {}

void main() {
  late MockApiClient apiClient;
  late NoteOperationsApiClient noteApi;

  setUp(() {
    apiClient = MockApiClient();
    noteApi = NoteOperationsApiClient(client: apiClient);
  });

  group('getDocument', () {
    test('parses successful response', () async {
      final response = MockResponse<Map<String, dynamic>>();
      when(() => response.data).thenReturn({
        'noteId': 'note-1',
        'revision': 5,
        'document': {'schemaVersion': 1, 'blocks': []},
        'serverTime': '2026-07-20T12:00:00Z',
      });
      when(
        () => apiClient.get<Map<String, dynamic>>(
          '/notes/note-1/document',
          queryParameters: any(named: 'queryParameters'),
          options: any(named: 'options'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer((_) async => response);

      final result = await noteApi.getDocument('note-1');

      expect(result.noteId, 'note-1');
      expect(result.revision, 5);
      expect(result.document, {'schemaVersion': 1, 'blocks': []});
      expect(result.serverTime, DateTime.utc(2026, 7, 20, 12));
    });

    test('throws NoteOperationsException on network error', () async {
      when(
        () => apiClient.get<Map<String, dynamic>>(
          '/notes/note-1/document',
          queryParameters: any(named: 'queryParameters'),
          options: any(named: 'options'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: ''),
          response: Response(
            requestOptions: RequestOptions(path: ''),
            statusCode: 400,
            data: {'error': 'INVALID_DELTA', 'message': 'Bad delta'},
          ),
        ),
      );

      expect(
        () => noteApi.getDocument('note-1'),
        throwsA(
          isA<NoteOperationsException>().having(
            (e) => e.errorCode,
            'errorCode',
            'INVALID_DELTA',
          ),
        ),
      );
    });
  });

  group('syncOperations', () {
    test('parses successful sync response', () async {
      final response = MockResponse<Map<String, dynamic>>();
      when(() => response.data).thenReturn({
        'accepted': [
          {
            'operationId': 'op-1',
            'revision': 6,
            'kind': 'text_delta',
          },
        ],
        'finalRevision': 6,
        'remoteOperations': [
          {
            'operationId': 'op-2',
            'noteId': 'note-1',
            'revision': 5,
            'baseRevision': 4,
            'kind': 'text_delta',
            'blockId': 'block-1',
            'payload': {'ops': [{'retain': 1}]},
            'createdAt': '2026-07-20T12:00:00Z',
          },
        ],
        'serverTime': '2026-07-20T12:00:01Z',
      });
      when(
        () => apiClient.post<Map<String, dynamic>>(
          '/notes/note-1/operations:sync',
          data: any(named: 'data'),
          queryParameters: any(named: 'queryParameters'),
          options: any(named: 'options'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer((_) async => response);

      final request = SyncRequest(
        knownRevision: 4,
        operations: [
          OperationRequest(
            operationId: 'op-1',
            baseRevision: 4,
            kind: 'text_delta',
            payload: {'ops': [{'insert': 'hello'}]},
          ),
        ],
        clientId: 'client-1',
      );

      final result = await noteApi.syncOperations('note-1', request);

      expect(result.accepted, hasLength(1));
      expect(result.accepted.first.operationId, 'op-1');
      expect(result.finalRevision, 6);
      expect(result.remoteOperations, hasLength(1));
      expect(result.remoteOperations.first.noteId, 'note-1');
    });
  });

  group('getOperationsSince', () {
    test('parses operations list', () async {
      final response = MockResponse<Map<String, dynamic>>();
      when(() => response.data).thenReturn({
        'operations': [
          {
            'operationId': 'op-1',
            'noteId': 'note-1',
            'revision': 5,
            'baseRevision': 4,
            'kind': 'text_delta',
            'payload': {'ops': []},
            'createdAt': '2026-07-20T12:00:00Z',
          },
        ],
        'finalRevision': 5,
      });
      when(
        () => apiClient.get<Map<String, dynamic>>(
          '/notes/note-1/operations',
          queryParameters: any(named: 'queryParameters'),
          options: any(named: 'options'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer((_) async => response);

      final result = await noteApi.getOperationsSince('note-1', 4);

      expect(result.operations, hasLength(1));
    });
  });

  group('OperationRequest serialization', () {
    test('toJson produces correct map', () {
      final request = OperationRequest(
        operationId: 'op-1',
        baseRevision: 0,
        kind: 'create_block',
        blockId: 'block-1',
        payload: {'type': 'paragraph', 'afterBlockId': null},
      );

      final json = request.toJson();

      expect(json['operationId'], 'op-1');
      expect(json['baseRevision'], 0);
      expect(json['kind'], 'create_block');
      expect(json['blockId'], 'block-1');
      expect(json['payload'], {'type': 'paragraph', 'afterBlockId': null});
    });

    test('toJson omits blockId when null', () {
      final request = OperationRequest(
        operationId: 'op-2',
        baseRevision: 1,
        kind: 'text_delta',
        payload: {'ops': []},
      );

      final json = request.toJson();

      expect(json.containsKey('blockId'), false);
    });
  });

  group('SyncRequest serialization', () {
    test('toJson produces correct map', () {
      final request = SyncRequest(
        knownRevision: 5,
        operations: [
          OperationRequest(
            operationId: 'op-1',
            baseRevision: 5,
            kind: 'text_delta',
            payload: {'ops': []},
          ),
        ],
        clientId: 'client-1',
      );

      final json = request.toJson();

      expect(json['knownRevision'], 5);
      expect(json['operations'], hasLength(1));
      expect(json['clientId'], 'client-1');
    });
  });
}
