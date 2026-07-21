import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:supanotes/core/database/daos/note_operations_dao.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/sync/note_operations_sync_service.dart';
import 'package:supanotes/features/notes/data/note_operations_api.dart';

class MockNoteOperationsDao extends Mock implements NoteOperationsDao {}

class MockNoteOperationsApiClient extends Mock
    implements NoteOperationsApiClient {}

void main() {
  late MockNoteOperationsDao mockDao;
  late MockNoteOperationsApiClient mockApi;
  late NoteOperationsSyncService service;

  setUpAll(() {
    registerFallbackValue(
      PendingNoteOperationsCompanion.insert(
        operationId: 'fallback',
        noteId: 'fallback',
        baseRevision: 0,
        ordinal: 0,
        kind: 'fallback',
        payloadJson: '{}',
        createdAt: DateTime.utc(2026, 1, 1),
      ),
    );
    registerFallbackValue(
      LocalNoteDocumentsCompanion.insert(
        noteId: 'fallback',
        revision: 0,
        documentJson: '{}',
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    );
    registerFallbackValue(
      SyncRequest(
        knownRevision: 0,
        operations: [],
        clientId: 'fallback',
      ),
    );
    registerFallbackValue(
      NoteSyncErrorsCompanion.insert(
        operationId: 'fallback',
        noteId: 'fallback',
        errorCode: 'FALLBACK',
        message: 'fallback',
        payloadJson: '{}',
        createdAt: DateTime.utc(2026, 1, 1),
      ),
    );
  });

  setUp(() {
    mockDao = MockNoteOperationsDao();
    mockApi = MockNoteOperationsApiClient();
    service = NoteOperationsSyncService(
      api: mockApi,
      dao: mockDao,
      clientId: 'test-client',
    );
  });

  group('enqueueOperation', () {
    test('inserts operation with correct ordinal', () async {
      when(() => mockDao.getPendingOperations('note-1'))
          .thenAnswer((_) async => []);
      when(
        () => mockDao.insertPendingOperation(any()),
      ).thenAnswer((_) async {});

      await service.enqueueOperation(
        'note-1',
        OperationRequest(
          operationId: 'op-1',
          baseRevision: 0,
          kind: 'create_block',
          payload: {},
        ),
      );

      verify(
        () => mockDao.insertPendingOperation(
          any(that: isA<PendingNoteOperationsCompanion>()),
        ),
      ).called(1);
    });

    test('increments ordinal for subsequent operations', () async {
      final existing = [
        PendingNoteOperationData(
          operationId: 'op-0',
          noteId: 'note-1',
          baseRevision: 0,
          ordinal: 0,
          kind: 'create_block',
          payloadJson: '{}',
          createdAt: DateTime.utc(2026, 7, 20),
          attemptCount: 0,
          blockId: null,
          lastAttemptAt: null,
        ),
      ];
      when(() => mockDao.getPendingOperations('note-1'))
          .thenAnswer((_) async => existing);
      when(
        () => mockDao.insertPendingOperation(any()),
      ).thenAnswer((_) async {});

      await service.enqueueOperation(
        'note-1',
        OperationRequest(
          operationId: 'op-2',
          baseRevision: 1,
          kind: 'text_delta',
          payload: {'ops': []},
        ),
      );

      final captured = verify(
        () => mockDao.insertPendingOperation(
          captureAny(that: isA<PendingNoteOperationsCompanion>()),
        ),
      ).captured.first as PendingNoteOperationsCompanion;

      expect(captured.ordinal.value, 1);
    });
  });

  group('syncPending', () {
    test('returns early when no pending operations', () async {
      when(() => mockDao.getPendingOperations('note-1'))
          .thenAnswer((_) async => []);
      when(() => mockDao.watchNoteDocument('note-1'))
          .thenAnswer((_) => Stream.value(null));

      final result = await service.syncPending('note-1');

      expect(result.acceptedCount, 0);
      expect(result.rejectedCount, 0);
      expect(result.finalRevision, 0);
    });

    test('sends operations and deletes accepted', () async {
      final ops = [
        PendingNoteOperationData(
          operationId: 'op-1',
          noteId: 'note-1',
          baseRevision: 0,
          ordinal: 0,
          kind: 'create_block',
          payloadJson: '{"type":"paragraph"}',
          createdAt: DateTime.utc(2026, 7, 20),
          attemptCount: 0,
          blockId: null,
          lastAttemptAt: null,
        ),
      ];
      when(() => mockDao.getPendingOperations('note-1'))
          .thenAnswer((_) async => ops);
      when(() => mockDao.watchNoteDocument('note-1'))
          .thenAnswer((_) => Stream.value(null));
      when(
        () => mockApi.syncOperations(
          'note-1',
          any(that: isA<SyncRequest>()),
        ),
      ).thenAnswer(
        (_) async => SyncResponse(
          accepted: [
            AcceptedOperation(
              operationId: 'op-1',
              revision: 1,
              kind: 'create_block',
            ),
          ],
          finalRevision: 1,
          remoteOperations: [],
          serverTime: DateTime.utc(2026, 7, 20, 12),
        ),
      );
      when(() => mockDao.deletePendingOperation('op-1'))
          .thenAnswer((_) async {});
      when(
        () => mockDao.upsertNoteDocument(any()),
      ).thenAnswer((_) async {});

      final result = await service.syncPending('note-1');

      expect(result.acceptedCount, 1);
      expect(result.rejectedCount, 0);
      expect(result.finalRevision, 1);
      verify(() => mockDao.deletePendingOperation('op-1')).called(1);
    });

    test('stores sync errors on api failure', () async {
      final ops = [
        PendingNoteOperationData(
          operationId: 'op-1',
          noteId: 'note-1',
          baseRevision: 0,
          ordinal: 0,
          kind: 'create_block',
          payloadJson: '{}',
          createdAt: DateTime.utc(2026, 7, 20),
          attemptCount: 0,
          blockId: null,
          lastAttemptAt: null,
        ),
      ];
      when(() => mockDao.getPendingOperations('note-1'))
          .thenAnswer((_) async => ops);
      when(() => mockDao.watchNoteDocument('note-1'))
          .thenAnswer((_) => Stream.value(null));
      when(
        () => mockApi.syncOperations('note-1', any()),
      ).thenThrow(
        NoteOperationsException(
          errorCode: 'INVALID_DELTA',
          message: 'Bad delta',
        ),
      );
      when(() => mockDao.incrementAttempt('op-1')).thenAnswer((_) async {});
      when(
        () => mockDao.insertSyncError(any()),
      ).thenAnswer((_) async {});

      await expectLater(
        () => service.syncPending('note-1'),
        throwsA(isA<NoteOperationsException>()),
      );

      verify(() => mockDao.incrementAttempt('op-1')).called(1);
      verify(() => mockDao.insertSyncError(any())).called(1);
    });
  });

  group('pollRemoteOperations', () {
    test('updates document when new operations exist', () async {
      when(() => mockDao.watchNoteDocument('note-1'))
          .thenAnswer((_) => Stream.value(
                LocalNoteDocumentData(
                  noteId: 'note-1',
                  revision: 3,
                  documentJson: '{"old": true}',
                  updatedAt: DateTime.utc(2026, 7, 20, 10),
                ),
              ));
      when(
        () => mockApi.getOperationsSince('note-1', 3),
      ).thenAnswer(
        (_) async => OperationsListResponse(
          operations: [
            Operation(
              operationId: 'op-3',
              noteId: 'note-1',
              revision: 4,
              baseRevision: 3,
              kind: 'text_delta',
              payload: {'ops': []},
              createdAt: DateTime.utc(2026, 7, 20, 11),
            ),
          ],
        ),
      );
      when(
        () => mockApi.getDocument('note-1'),
      ).thenAnswer(
        (_) async => NoteDocumentResponse(
          noteId: 'note-1',
          revision: 4,
          document: {'blocks': []},
          serverTime: DateTime.utc(2026, 7, 20, 11),
        ),
      );
      when(
        () => mockDao.upsertNoteDocument(any()),
      ).thenAnswer((_) async {});

      await service.pollRemoteOperations('note-1');

      verify(() => mockDao.upsertNoteDocument(any())).called(1);
    });

    test('does nothing when no new operations', () async {
      when(() => mockDao.watchNoteDocument('note-1'))
          .thenAnswer((_) => Stream.value(
                LocalNoteDocumentData(
                  noteId: 'note-1',
                  revision: 3,
                  documentJson: '{}',
                  updatedAt: DateTime.utc(2026, 7, 20, 10),
                ),
              ));
      when(
        () => mockApi.getOperationsSince('note-1', 3),
      ).thenAnswer(
        (_) async => OperationsListResponse(
          operations: [],
        ),
      );

      await service.pollRemoteOperations('note-1');

      verifyNever(() => mockDao.upsertNoteDocument(any()));
    });

    test('handles api error gracefully', () async {
      when(() => mockDao.watchNoteDocument('note-1'))
          .thenAnswer((_) => Stream.value(null));
      when(
        () => mockApi.getOperationsSince('note-1', 0),
      ).thenThrow(
        NoteOperationsException(
          errorCode: 'NETWORK_ERROR',
          message: 'timeout',
        ),
      );

      await service.pollRemoteOperations('note-1');

      verifyNever(() => mockDao.upsertNoteDocument(any()));
    });
  });

  test('getConfirmedDocument returns document from dao', () async {
    final doc = LocalNoteDocumentData(
      noteId: 'note-1',
      revision: 5,
      documentJson: '{"blocks": []}',
      updatedAt: DateTime.utc(2026, 7, 20),
    );
    when(() => mockDao.watchNoteDocument('note-1'))
        .thenAnswer((_) => Stream.value(doc));

    final result = await service.getConfirmedDocument('note-1');

    expect(result, isNotNull);
    expect(result!.revision, 5);
  });
}
