import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:super_editor/super_editor.dart';

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
      SyncRequest(knownRevision: 0, operations: [], clientId: 'fallback'),
    );
    registerFallbackValue(
      SyncSessionsCompanion.insert(
        noteId: 'fallback',
        knownRevision: 0,
        operationIds: '[]',
        startedAt: '2026-01-01T00:00:00.000',
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
      actorId: 'test-actor',
    );

    when(() => mockDao.getPendingOperations(any())).thenAnswer((_) async => []);
    when(
      () => mockDao.getPendingOperations(any(), status: any(named: 'status')),
    ).thenAnswer((_) async => []);
    when(
      () => mockDao.watchNoteDocument(any()),
    ).thenAnswer((_) => Stream.value(null));
    when(() => mockDao.getSyncSession(any())).thenAnswer((_) async => null);
    when(() => mockDao.markInFlight(any(), any())).thenAnswer((_) async {});
    when(() => mockDao.upsertSyncSession(any())).thenAnswer((_) async {});
    when(() => mockDao.deleteAccepted(any())).thenAnswer((_) async {});
    when(
      () => mockDao.replacePendingOps(any(), any()),
    ).thenAnswer((_) async {});
    when(() => mockDao.upsertNoteDocument(any())).thenAnswer((_) async {});
    when(() => mockDao.deleteSyncSession(any())).thenAnswer((_) async {});
    when(() => mockDao.runInTransaction(any())).thenAnswer((invocation) async {
      final fn = invocation.positionalArguments[0] as Future<void> Function();
      await fn();
    });
    when(
      () => mockDao.getProjectedOutboxOperationCount(any()),
    ).thenAnswer((_) async => 0);
  });

  group('enqueueOperation', () {
    test('inserts operation with correct ordinal', () async {
      when(
        () => mockDao.getPendingOperations('note-1'),
      ).thenAnswer((_) async => []);
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
      final existing = <PendingNoteOperationData>[
        PendingNoteOperationData(
          operationId: 'op-0',
          noteId: 'note-1',
          baseRevision: 0,
          ordinal: 0,
          kind: 'create_block',
          payloadJson: '{}',
          createdAt: DateTime.utc(2026, 7, 20),
          attemptCount: 0,
          status: 'pending',
          blockId: null,
          lastAttemptAt: null,
        ),
      ];
      when(
        () => mockDao.getPendingOperations('note-1'),
      ).thenAnswer((_) async => existing);
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

      final captured =
          verify(
                () => mockDao.insertPendingOperation(
                  captureAny(that: isA<PendingNoteOperationsCompanion>()),
                ),
              ).captured.first
              as PendingNoteOperationsCompanion;

      expect(captured.ordinal.value, 1);
    });
  });

  group('syncPending', () {
    test('returns early when no pending operations', () async {
      final result = await service.syncPending('note-1');

      expect(result.acceptedCount, 0);
      expect(result.finalRevision, 0);
      expect(result.remoteOperations, isEmpty);
    });
  });

  test('generateOperationId returns a UUID', () {
    final id = service.generateOperationId();
    expect(id, isA<String>());
    expect(id.length, greaterThan(0));
  });

  test('encodePayload converts editor values to JSON', () {
    final json = NoteOperationsSyncService.encodePayload({
      'metadata': {'blockType': const NamedAttribution('task')},
    });

    expect(json, '{"metadata":{"blockType":"task"}}');
  });

  test('getConfirmedDocument returns document from dao', () async {
    final doc = LocalNoteDocumentData(
      noteId: 'note-1',
      revision: 5,
      documentJson: '{"blocks": []}',
      updatedAt: DateTime.utc(2026, 7, 20),
    );
    when(
      () => mockDao.watchNoteDocument('note-1'),
    ).thenAnswer((_) => Stream.value(doc));

    final result = await service.getConfirmedDocument('note-1');

    expect(result, isNotNull);
    expect(result!.revision, 5);
  });
}
