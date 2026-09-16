import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supanotes/core/database/daos/note_operations_dao.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/sync/note_operations_sync_service.dart';
import 'package:supanotes/features/notes/editor/sync/note_sync_client.dart';
import 'package:super_editor/super_editor.dart';

class MockNoteOperationsDao extends Mock implements NoteOperationsDao {}

class MockNoteSyncClient extends Mock implements NoteSyncClient {}

void main() {
  late MockNoteOperationsDao mockDao;
  late MockNoteSyncClient mockSyncClient;
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
        createdAt: DateTime.utc(2026),
      ),
    );
    registerFallbackValue(
      LocalNoteDocumentsCompanion.insert(
        noteId: 'fallback',
        revision: 0,
        documentJson: '{}',
        updatedAt: DateTime.utc(2026),
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
    mockSyncClient = MockNoteSyncClient();
    service = NoteOperationsSyncService(
      syncClient: mockSyncClient,
      dao: mockDao,
      clientId: 'test-client',
      actorId: 'test-actor',
    );

    when(
      () => mockDao.getPendingOperations(
        any(),
        ownerUserId: any(named: 'ownerUserId'),
      ),
    ).thenAnswer((_) async => []);
    when(
      () => mockDao.getPendingOperations(
        any(),
        status: any(named: 'status'),
        ownerUserId: any(named: 'ownerUserId'),
      ),
    ).thenAnswer((_) async => []);
    when(
      () => mockDao.watchNoteDocument(any()),
    ).thenAnswer((_) => Stream.value(null));
    when(
      () =>
          mockDao.getSyncSession(any(), ownerUserId: any(named: 'ownerUserId')),
    ).thenAnswer((_) async => null);
    when(() => mockDao.getAnySyncSession(any())).thenAnswer((_) async => null);
    when(() => mockDao.getNoteOwnerId(any())).thenAnswer((_) async => null);
    when(() => mockDao.adoptLegacyRows(any(), any())).thenAnswer((_) async {});
    when(
      () => mockDao.markInFlightInTransaction(
        any(),
        any(),
        ownerUserId: any(named: 'ownerUserId'),
      ),
    ).thenAnswer((_) async {});
    when(() => mockDao.upsertSyncSession(any())).thenAnswer((_) async {});
    when(
      () => mockDao.deleteAcceptedInTransaction(
        any(),
        noteId: any(named: 'noteId'),
        ownerUserId: any(named: 'ownerUserId'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => mockDao.replacePendingOpsInTransaction(
        any(),
        any(),
        ownerUserId: any(named: 'ownerUserId'),
      ),
    ).thenAnswer((_) async {});
    when(() => mockDao.upsertNoteDocument(any())).thenAnswer((_) async {});
    when(
      () => mockDao.upsertNoteDocumentInTransaction(any()),
    ).thenAnswer((_) async {});
    when(
      () => mockDao.saveMaterializedDocumentInTransaction(
        noteId: any(named: 'noteId'),
        documentJson: any(named: 'documentJson'),
        content: any(named: 'content'),
        excerpt: any(named: 'excerpt'),
        updatedAt: any(named: 'updatedAt'),
      ),
    ).thenAnswer((_) async {});
    when(() => mockDao.deleteSyncSession(any())).thenAnswer((_) async {});
    when(
      () => mockDao.deleteSyncSession(
        any(),
        ownerUserId: any(named: 'ownerUserId'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => mockDao.deleteSyncSessionInTransaction(
        any(),
        ownerUserId: any(named: 'ownerUserId'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => mockDao.insertPendingOperationsInTransaction(any()),
    ).thenAnswer((_) async {});
    when(
      () => mockDao.updatePendingOpsStatus(
        any(),
        any(),
        any(),
        ownerUserId: any(named: 'ownerUserId'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => mockDao.deletePendingOpsByStatus(
        any(),
        any(),
        ownerUserId: any(named: 'ownerUserId'),
      ),
    ).thenAnswer((_) async {});
    when(() => mockDao.runInTransaction(any())).thenAnswer((invocation) async {
      final fn = invocation.positionalArguments[0] as Future<void> Function();
      await fn();
    });
    when(
      () => mockDao.getProjectedOutboxOperationCount(
        any(),
        ownerUserId: any(named: 'ownerUserId'),
      ),
    ).thenAnswer((_) async => 0);
  });

  group('enqueueOperation', () {
    test('inserts operation with correct ordinal', () async {
      when(
        () => mockDao.getPendingOperations('note-1', ownerUserId: 'test-actor'),
      ).thenAnswer((_) async => []);
      when(
        () => mockDao.insertPendingOperationsInTransaction(any()),
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
        () => mockDao.insertPendingOperationsInTransaction(
          any(that: isA<List<PendingNoteOperationsCompanion>>()),
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
        ),
      ];
      when(
        () => mockDao.getPendingOperations('note-1', ownerUserId: 'test-actor'),
      ).thenAnswer((_) async => existing);
      when(
        () => mockDao.insertPendingOperationsInTransaction(any()),
      ).thenAnswer((_) async {});

      await service.enqueueOperation(
        'note-1',
        OperationRequest(
          operationId: 'op-2',
          baseRevision: 99,
          kind: 'text_delta',
          payload: {'ops': []},
        ),
      );

      final captured =
          verify(
                () => mockDao.insertPendingOperationsInTransaction(
                  captureAny(that: isA<List<PendingNoteOperationsCompanion>>()),
                ),
              ).captured.first
              as List<PendingNoteOperationsCompanion>;

      expect(captured.single.ordinal.value, 1);
      expect(captured.single.baseRevision.value, 1);
    });

    test('uses the confirmed revision when the outbox is empty', () async {
      when(
        () => mockDao.getPendingOperations('note-1', ownerUserId: 'test-actor'),
      ).thenAnswer((_) async => []);
      when(() => mockDao.watchNoteDocument('note-1')).thenAnswer(
        (_) => Stream.value(
          LocalNoteDocumentData(
            noteId: 'note-1',
            revision: 7,
            documentJson: '{"blocks":[]}',
            updatedAt: DateTime.utc(2026, 7, 20),
          ),
        ),
      );
      when(
        () => mockDao.insertPendingOperationsInTransaction(any()),
      ).thenAnswer((_) async {});

      await service.enqueueOperation(
        'note-1',
        OperationRequest(
          operationId: 'op-1',
          baseRevision: 0,
          kind: 'create_block',
          payload: const {},
        ),
      );

      final captured =
          verify(
                () => mockDao.insertPendingOperationsInTransaction(
                  captureAny(that: isA<List<PendingNoteOperationsCompanion>>()),
                ),
              ).captured.single
              as List<PendingNoteOperationsCompanion>;

      expect(captured.single.baseRevision.value, 7);
    });

    test('persists an operation batch in one transaction', () async {
      when(
        () => mockDao.insertPendingOperationsInTransaction(any()),
      ).thenAnswer((_) async {});

      await service.enqueueOperations('note-1', [
        OperationRequest(
          operationId: 'op-1',
          baseRevision: 0,
          kind: 'create_block',
          payload: const {},
        ),
        OperationRequest(
          operationId: 'op-2',
          baseRevision: 1,
          kind: 'text_delta',
          payload: const {'ops': []},
        ),
      ]);

      verify(() => mockDao.runInTransaction(any())).called(1);
      verify(
        () => mockDao.insertPendingOperationsInTransaction(any()),
      ).called(1);
    });

    test('serializes concurrent outbox appends for the same note', () async {
      final stored = <PendingNoteOperationData>[];
      when(
        () => mockDao.getPendingOperations('note-1', ownerUserId: 'test-actor'),
      ).thenAnswer((_) async => List.of(stored));
      when(
        () => mockDao.insertPendingOperationsInTransaction(any()),
      ).thenAnswer((
        invocation,
      ) async {
        final ops =
            invocation.positionalArguments.single
                as List<PendingNoteOperationsCompanion>;
        for (final op in ops) {
          stored.add(
            PendingNoteOperationData(
              operationId: op.operationId.value,
              noteId: op.noteId.value,
              baseRevision: op.baseRevision.value,
              ordinal: op.ordinal.value,
              kind: op.kind.value,
              blockId: op.blockId.value,
              payloadJson: op.payloadJson.value,
              createdAt: op.createdAt.value,
              attemptCount: 0,
              status: 'pending',
            ),
          );
        }
      });

      await Future.wait([
        service.enqueueOperation(
          'note-1',
          OperationRequest(
            operationId: 'op-1',
            baseRevision: 0,
            kind: 'create_block',
            payload: const {},
          ),
        ),
        service.enqueueOperation(
          'note-1',
          OperationRequest(
            operationId: 'op-2',
            baseRevision: 1,
            kind: 'text_delta',
            payload: const {'ops': []},
          ),
        ),
      ]);

      expect(stored.map((op) => op.ordinal), [0, 1]);
      expect(stored.map((op) => op.operationId), ['op-1', 'op-2']);
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
