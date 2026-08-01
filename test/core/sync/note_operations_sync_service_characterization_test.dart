import 'dart:async';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/sync/note_operations_sync_service.dart';
import 'package:supanotes/features/notes/data/note_sync_client.dart';

void main() {
  group('NoteOperationsSyncService characterization', () {
    late AppDatabase db;
    late CharacterizationNoteSyncClient client;
    late NoteOperationsSyncService service;

    setUp(() {
      db = AppDatabase.test();
      client = CharacterizationNoteSyncClient();
      service = NoteOperationsSyncService(
        syncClient: client,
        dao: db.noteOperationsDao,
        clientId: 'client-1',
        actorId: 'user-1',
      );
    });

    tearDown(() async {
      await db.close();
    });

    test(
      'opening sees confirmed snapshot and pending projection from Drift',
      () async {
        await db.noteOperationsDao.upsertNoteDocument(
          LocalNoteDocumentsCompanion.insert(
            noteId: 'note-open',
            revision: 7,
            documentJson:
                '{"schemaVersion":1,"blocks":[{"id":"b1","type":"paragraph","text":"confirmed"}]}',
            updatedAt: DateTime.utc(2026, 7, 26),
          ),
        );
        await db.noteOperationsDao.insertPendingOperation(
          PendingNoteOperationsCompanion.insert(
            operationId: 'op-pending',
            noteId: 'note-open',
            ownerUserId: const Value('user-1'),
            baseRevision: 7,
            ordinal: 0,
            kind: 'text_delta',
            blockId: const Value('b1'),
            payloadJson: '{"delta":[{"insert":" local"}]}',
            createdAt: DateTime.utc(2026, 7, 26),
          ),
        );

        final confirmed = await service.getConfirmedDocument('note-open');
        final pending = await service.loadPendingProjection('note-open');

        expect(confirmed, isNotNull);
        expect(confirmed!.revision, 7);
        expect(confirmed.documentJson, contains('confirmed'));
        expect(pending, hasLength(1));
        expect(pending.single.operationId, 'op-pending');
      },
    );

    test(
      'editing enqueues local operation before network sync is required',
      () async {
        await service.enqueueOperation(
          'note-edit',
          OperationRequest(
            operationId: 'op-local',
            baseRevision: 3,
            kind: 'text_delta',
            blockId: 'b1',
            payload: const {
              'delta': [
                {'insert': 'local'},
              ],
            },
          ),
        );

        final pending = await db.noteOperationsDao.getPendingOperations(
          'note-edit',
        );

        expect(pending, hasLength(1));
        expect(pending.single.operationId, 'op-local');
        expect(pending.single.status, 'pending');
        expect(client.syncOperationCalls, 0);
      },
    );

    test(
      'sync creates persisted session then clears it after accepted response',
      () async {
        await seedConfirmedDocument(db, 'note-sync', revision: 4);
        await seedPendingOperation(db, 'note-sync', 'op-sync', baseRevision: 4);
        client.syncResponses.add(
          SyncResponse(
            accepted: [
              AcceptedOperation(
                operationId: 'op-sync',
                revision: 5,
                kind: 'text_delta',
                blockId: 'b1',
              ),
            ],
            finalRevision: 5,
            remoteOperations: const [],
            canonicalDocument: const {
              'schemaVersion': 1,
              'blocks': [
                {'id': 'b1', 'type': 'paragraph', 'text': 'server'},
              ],
            },
            serverTime: DateTime.utc(2026, 7, 26),
          ),
        );

        final result = await service.syncPending('note-sync');

        expect(result.finalRevision, 5);
        expect(await db.noteOperationsDao.getSyncSession('note-sync'), isNull);
        expect(
          await db.noteOperationsDao.getPendingOperations('note-sync'),
          isEmpty,
        );
        final confirmed = await db.noteOperationsDao
            .watchNoteDocument('note-sync')
            .first;
        expect(confirmed!.revision, 5);
        expect(confirmed.documentJson, contains('server'));
      },
    );

    test(
      'failed sync leaves in-flight operation and persisted session for resume',
      () async {
        await seedConfirmedDocument(db, 'note-fail', revision: 4);
        await seedPendingOperation(db, 'note-fail', 'op-fail', baseRevision: 4);
        client.syncError = StateError('network unavailable');

        await expectLater(
          service.syncPending('note-fail'),
          throwsA(isA<StateError>()),
        );

        final session = await db.noteOperationsDao.getSyncSession('note-fail');
        final inFlight = await db.noteOperationsDao.getPendingOperations(
          'note-fail',
        );
        expect(session, isNotNull);
        expect(session!.knownRevision, 4);
        expect(inFlight, hasLength(1));
        expect(inFlight.single.status, 'in_flight');
      },
    );

    test(
      'different account cannot overwrite a foreign persisted sync session',
      () async {
        await seedConfirmedDocument(db, 'note-account-scope', revision: 4);
        await db.noteOperationsDao.insertPendingOperation(
          PendingNoteOperationsCompanion.insert(
            operationId: 'op-user-b',
            noteId: 'note-account-scope',
            ownerUserId: const Value('user-b'),
            baseRevision: 4,
            ordinal: 0,
            kind: 'text_delta',
            blockId: const Value('b1'),
            payloadJson: '{"delta":[]}',
            createdAt: DateTime.utc(2026, 7, 26),
          ),
        );
        await db.noteOperationsDao.upsertSyncSession(
          SyncSessionsCompanion.insert(
            noteId: 'note-account-scope',
            ownerUserId: const Value('user-a'),
            knownRevision: 4,
            operationIds: '["op-user-a"]',
            startedAt: DateTime.utc(2026, 7, 26).toIso8601String(),
          ),
        );

        final clientB = CharacterizationNoteSyncClient();
        final serviceB = NoteOperationsSyncService(
          syncClient: clientB,
          dao: db.noteOperationsDao,
          clientId: 'client-b',
          actorId: 'user-b',
        );

        final result = await serviceB.syncPending('note-account-scope');

        expect(result.acceptedCount, 0);
        expect(result.isBlocked, isTrue);
        expect(result.blockedReason, 'foreign_sync_session');
        expect(clientB.syncOperationCalls, 0);
        expect(
          (await db.noteOperationsDao.getAnySyncSession(
            'note-account-scope',
          ))?.ownerUserId,
          'user-a',
        );
        expect(
          await db.noteOperationsDao.getPendingOperations(
            'note-account-scope',
            ownerUserId: 'user-b',
          ),
          hasLength(1),
        );
      },
    );

    test(
      'resume repairs mismatched persisted session before retrying pending work',
      () async {
        await seedConfirmedDocument(db, 'note-resume', revision: 4);
        await seedPendingOperation(
          db,
          'note-resume',
          'op-resume',
          baseRevision: 4,
          status: 'in_flight',
        );
        await db.noteOperationsDao.upsertSyncSession(
          SyncSessionsCompanion.insert(
            noteId: 'note-resume',
            ownerUserId: const Value('user-1'),
            knownRevision: 4,
            operationIds: '["different-op"]',
            startedAt: DateTime.utc(2026, 7, 26).toIso8601String(),
          ),
        );
        client.syncResponses.add(
          SyncResponse(
            accepted: [
              AcceptedOperation(
                operationId: 'op-resume',
                revision: 5,
                kind: 'text_delta',
                blockId: 'b1',
              ),
            ],
            finalRevision: 5,
            remoteOperations: const [],
            canonicalDocument: const {'schemaVersion': 1, 'blocks': []},
            serverTime: DateTime.utc(2026, 7, 26),
          ),
        );

        await service.syncPending('note-resume');

        expect(
          client.lastSyncRequest!.operations.single.operationId,
          'op-resume',
        );
        expect(
          await db.noteOperationsDao.getSyncSession('note-resume'),
          isNull,
        );
        expect(
          await db.noteOperationsDao.getPendingOperations('note-resume'),
          isEmpty,
        );
      },
    );

    test('two notes progress through independent serialized queues', () async {
      await seedConfirmedDocument(db, 'note-a', revision: 1);
      await seedConfirmedDocument(db, 'note-b', revision: 10);
      await seedPendingOperation(db, 'note-a', 'op-a', baseRevision: 1);
      await seedPendingOperation(db, 'note-b', 'op-b', baseRevision: 10);
      final releaseA = Completer<void>();
      client.onSync = (noteId, request) async {
        if (noteId == 'note-a') {
          await releaseA.future;
        }
        return syncResponseFor(
          request.operations.single.operationId,
          request.operations.single.baseRevision + 1,
        );
      };

      final futureA = service.syncPending('note-a');
      await pumpEventQueue();
      final futureB = service.syncPending('note-b');

      final resultB = await futureB;
      expect(resultB.acceptedOperationIds, contains('op-b'));

      releaseA.complete();
      final resultA = await futureA;
      expect(resultA.acceptedOperationIds, contains('op-a'));
    });

    test('two concurrent sync attempts for one note are serialized', () async {
      await seedConfirmedDocument(db, 'note-one', revision: 1);
      await seedPendingOperation(db, 'note-one', 'op-one', baseRevision: 1);
      final enteredFirstSync = Completer<void>();
      final releaseFirstSync = Completer<void>();
      client.onSync = (noteId, request) async {
        if (!enteredFirstSync.isCompleted) {
          enteredFirstSync.complete();
          await releaseFirstSync.future;
        }
        return syncResponseFor(
          request.operations.single.operationId,
          request.operations.single.baseRevision + 1,
        );
      };

      final first = service.syncPending('note-one');
      await enteredFirstSync.future;
      final second = service.syncPending('note-one');
      await pumpEventQueue();

      expect(client.syncOperationCalls, 1);
      releaseFirstSync.complete();

      final firstResult = await first;
      final secondResult = await second;
      expect(firstResult.acceptedOperationIds, contains('op-one'));
      expect(secondResult.acceptedCount, 0);
      expect(client.syncOperationCalls, 1);
    });

    test(
      'telemetry snapshot exposes outbox, persisted session and failures',
      () async {
        await seedConfirmedDocument(db, 'note-observe', revision: 4);
        await seedPendingOperation(
          db,
          'note-observe',
          'op-observe',
          baseRevision: 4,
        );
        await db.noteOperationsDao.upsertSyncSession(
          SyncSessionsCompanion.insert(
            noteId: 'note-observe',
            ownerUserId: const Value('user-1'),
            knownRevision: 4,
            operationIds: '["op-observe"]',
            startedAt: DateTime.utc(2026, 7, 26).toIso8601String(),
          ),
        );
        await db.noteOperationsDao.insertSyncError(
          NoteSyncErrorsCompanion.insert(
            noteId: 'note-observe',
            operationId: 'op-observe',
            errorCode: 'NETWORK',
            message: 'network unavailable',
            payloadJson: '{}',
            createdAt: DateTime.utc(2026, 7, 26),
          ),
        );

        final snapshot = await service.telemetrySnapshot('note-observe');

        expect(snapshot.noteId, 'note-observe');
        expect(snapshot.outboxOperationCount, 1);
        expect(snapshot.syncErrorCount, 1);
        expect(snapshot.hasPersistedSession, isTrue);
      },
    );

    test(
      'two edit clients with independent databases converge through sync and poll',
      () async {
        const noteId = 'shared-note';
        final dbA = AppDatabase.test();
        final dbB = AppDatabase.test();
        final backend = SharedOtBackend();
        final serviceA = NoteOperationsSyncService(
          syncClient: SharedBackendNoteSyncClient(
            backend: backend,
            actorId: 'user-a',
          ),
          dao: dbA.noteOperationsDao,
          clientId: 'client-a',
          actorId: 'user-a',
        );
        final serviceB = NoteOperationsSyncService(
          syncClient: SharedBackendNoteSyncClient(
            backend: backend,
            actorId: 'user-b',
          ),
          dao: dbB.noteOperationsDao,
          clientId: 'client-b',
          actorId: 'user-b',
        );
        addTearDown(dbA.close);
        addTearDown(dbB.close);

        await seedConfirmedDocument(dbA, noteId, revision: 0);
        await seedConfirmedDocument(dbB, noteId, revision: 0);
        await serviceA.enqueueOperation(
          noteId,
          OperationRequest(
            operationId: 'op-a',
            baseRevision: 0,
            kind: 'text_delta',
            blockId: 'b1',
            payload: const {'label': 'edit-a'},
          ),
        );
        await serviceB.enqueueOperation(
          noteId,
          OperationRequest(
            operationId: 'op-b',
            baseRevision: 0,
            kind: 'text_delta',
            blockId: 'b1',
            payload: const {'label': 'edit-b'},
          ),
        );

        await serviceA.syncPending(noteId);
        await serviceB.syncPending(noteId);
        await serviceA.pollAndReconcile(noteId);

        final docA = await dbA.noteOperationsDao
            .watchNoteDocument(noteId)
            .first;
        final docB = await dbB.noteOperationsDao
            .watchNoteDocument(noteId)
            .first;
        expect(docA!.revision, 2);
        expect(docB!.revision, 2);
        expect(docA.documentJson, contains('edit-a'));
        expect(docA.documentJson, contains('edit-b'));
        expect(docB.documentJson, contains('edit-a'));
        expect(docB.documentJson, contains('edit-b'));
        expect(
          await dbA.noteOperationsDao.getPendingOperations(noteId),
          isEmpty,
        );
        expect(
          await dbB.noteOperationsDao.getPendingOperations(noteId),
          isEmpty,
        );
      },
    );

    test(
      'offline clients keep outbox, then restart and reconnect to canonical state',
      () async {
        const noteId = 'offline-shared-note';
        final dbA = AppDatabase.test();
        final dbB = AppDatabase.test();
        final backend = SharedOtBackend();
        final clientA = SharedBackendNoteSyncClient(
          backend: backend,
          actorId: 'user-a',
          online: false,
        );
        final clientB = SharedBackendNoteSyncClient(
          backend: backend,
          actorId: 'user-b',
          online: false,
        );
        final serviceA = NoteOperationsSyncService(
          syncClient: clientA,
          dao: dbA.noteOperationsDao,
          clientId: 'client-a',
          actorId: 'user-a',
        );
        final serviceB = NoteOperationsSyncService(
          syncClient: clientB,
          dao: dbB.noteOperationsDao,
          clientId: 'client-b',
          actorId: 'user-b',
        );
        addTearDown(dbA.close);
        addTearDown(dbB.close);

        await seedConfirmedDocument(dbA, noteId, revision: 0);
        await seedConfirmedDocument(dbB, noteId, revision: 0);
        await serviceA.enqueueOperation(
          noteId,
          OperationRequest(
            operationId: 'op-offline-a',
            baseRevision: 0,
            kind: 'text_delta',
            blockId: 'b1',
            payload: const {'label': 'offline-a'},
          ),
        );
        await serviceB.enqueueOperation(
          noteId,
          OperationRequest(
            operationId: 'op-offline-b',
            baseRevision: 0,
            kind: 'text_delta',
            blockId: 'b1',
            payload: const {'label': 'offline-b'},
          ),
        );

        await expectLater(
          serviceA.syncPending(noteId),
          throwsA(isA<StateError>()),
        );
        await expectLater(
          serviceB.syncPending(noteId),
          throwsA(isA<StateError>()),
        );
        expect(
          await dbA.noteOperationsDao.getPendingOperations(noteId),
          hasLength(1),
        );
        expect(
          await dbB.noteOperationsDao.getPendingOperations(noteId),
          hasLength(1),
        );
        expect(await dbA.noteOperationsDao.getSyncSession(noteId), isNotNull);
        expect(await dbB.noteOperationsDao.getSyncSession(noteId), isNotNull);

        clientA.online = true;
        clientB.online = true;
        final restartedServiceA = NoteOperationsSyncService(
          syncClient: clientA,
          dao: dbA.noteOperationsDao,
          clientId: 'client-a',
          actorId: 'user-a',
        );
        await restartedServiceA.syncPending(noteId);
        await serviceB.syncPending(noteId);
        await restartedServiceA.pollAndReconcile(noteId);

        final docA = await dbA.noteOperationsDao
            .watchNoteDocument(noteId)
            .first;
        final docB = await dbB.noteOperationsDao
            .watchNoteDocument(noteId)
            .first;
        expect(docA!.documentJson, contains('offline-a'));
        expect(docA.documentJson, contains('offline-b'));
        expect(docB!.documentJson, contains('offline-a'));
        expect(docB.documentJson, contains('offline-b'));
        expect(await dbA.noteOperationsDao.getSyncSession(noteId), isNull);
        expect(await dbB.noteOperationsDao.getSyncSession(noteId), isNull);
      },
    );

    test(
      'task occurrence reopen sync keeps a different client occurrence intact',
      () async {
        const noteId = 'task-occurrence-shared-note';
        final dbA = AppDatabase.test();
        final dbB = AppDatabase.test();
        final backend = SharedOtBackend();
        final serviceA = NoteOperationsSyncService(
          syncClient: SharedBackendNoteSyncClient(
            backend: backend,
            actorId: 'user-a',
          ),
          dao: dbA.noteOperationsDao,
          clientId: 'client-a',
          actorId: 'user-a',
        );
        final serviceB = NoteOperationsSyncService(
          syncClient: SharedBackendNoteSyncClient(
            backend: backend,
            actorId: 'user-b',
          ),
          dao: dbB.noteOperationsDao,
          clientId: 'client-b',
          actorId: 'user-b',
        );
        addTearDown(dbA.close);
        addTearDown(dbB.close);

        await seedConfirmedDocument(dbA, noteId, revision: 0);
        await seedConfirmedDocument(dbB, noteId, revision: 0);
        await serviceA.enqueueOperation(
          noteId,
          OperationRequest(
            operationId: 'reopen-occurrence-a',
            baseRevision: 0,
            kind: 'complete_task_occurrence',
            payload: const {
              'taskId': 'task-1',
              'scheduledAt': '2026-07-26T09:00:00.000Z',
              'completedAt': null,
            },
          ),
        );
        await serviceB.enqueueOperation(
          noteId,
          OperationRequest(
            operationId: 'complete-occurrence-b',
            baseRevision: 0,
            kind: 'complete_task_occurrence',
            payload: const {
              'taskId': 'task-1',
              'scheduledAt': '2026-07-27T09:00:00.000Z',
              'completedAt': '2026-07-27T10:00:00.000Z',
            },
          ),
        );

        await serviceA.syncPending(noteId);
        await serviceB.syncPending(noteId);
        await serviceA.pollAndReconcile(noteId);

        final docA = await dbA.noteOperationsDao
            .watchNoteDocument(noteId)
            .first;
        final docB = await dbB.noteOperationsDao
            .watchNoteDocument(noteId)
            .first;
        expect(docA!.documentJson, contains('2026-07-26T09:00:00.000Z'));
        expect(docA.documentJson, contains('reopened'));
        expect(docA.documentJson, contains('2026-07-27T09:00:00.000Z'));
        expect(docA.documentJson, contains('2026-07-27T10:00:00.000Z'));
        expect(docB!.documentJson, docA.documentJson);
      },
    );
  });
}

Future<void> seedConfirmedDocument(
  AppDatabase db,
  String noteId, {
  required int revision,
}) {
  return db.noteOperationsDao.upsertNoteDocument(
    LocalNoteDocumentsCompanion.insert(
      noteId: noteId,
      revision: revision,
      documentJson:
          '{"schemaVersion":1,"blocks":[{"id":"b1","type":"paragraph","text":"confirmed"}]}',
      updatedAt: DateTime.utc(2026, 7, 26),
    ),
  );
}

Future<void> seedPendingOperation(
  AppDatabase db,
  String noteId,
  String operationId, {
  required int baseRevision,
  String status = 'pending',
}) {
  return db.noteOperationsDao.insertPendingOperation(
    PendingNoteOperationsCompanion.insert(
      operationId: operationId,
      noteId: noteId,
      ownerUserId: const Value('user-1'),
      baseRevision: baseRevision,
      ordinal: 0,
      kind: 'text_delta',
      blockId: const Value('b1'),
      payloadJson: '{"delta":[{"insert":"local"}]}',
      createdAt: DateTime.utc(2026, 7, 26),
      status: Value(status),
    ),
  );
}

SyncResponse syncResponseFor(String operationId, int finalRevision) {
  return SyncResponse(
    accepted: [
      AcceptedOperation(
        operationId: operationId,
        revision: finalRevision,
        kind: 'text_delta',
        blockId: 'b1',
      ),
    ],
    finalRevision: finalRevision,
    remoteOperations: const [],
    canonicalDocument: const {'schemaVersion': 1, 'blocks': []},
    serverTime: DateTime.utc(2026, 7, 26),
  );
}

class CharacterizationNoteSyncClient implements NoteSyncClient {
  final List<SyncResponse> syncResponses = [];
  Future<SyncResponse> Function(String noteId, SyncRequest request)? onSync;
  Object? syncError;
  int syncOperationCalls = 0;
  SyncRequest? lastSyncRequest;

  @override
  Future<NoteDocumentResponse> getDocument(String noteId) {
    throw UnimplementedError('getDocument is not used by these tests');
  }

  @override
  Future<NoteDocumentResponse?> fetchDocument(String noteId) {
    throw UnimplementedError('fetchDocument is not used by these tests');
  }

  @override
  Future<List<Map<String, dynamic>>> listNotes({
    int limit = 100,
    DateTime? cursorUpdatedAt,
    String? cursorId,
  }) {
    throw UnimplementedError('listNotes is not used by these tests');
  }

  @override
  Future<void> deleteNote(String noteId) {
    throw UnimplementedError('deleteNote is not used by these tests');
  }

  @override
  Future<OperationsListResponse> getOperationsSince(
    String noteId,
    int afterRevision,
  ) async {
    return OperationsListResponse(operations: const []);
  }

  @override
  Future<SyncResponse> syncOperations(
    String noteId,
    SyncRequest request,
  ) async {
    syncOperationCalls++;
    lastSyncRequest = request;
    final error = syncError;
    if (error != null) {
      throw error;
    }
    final handler = onSync;
    if (handler != null) {
      return handler(noteId, request);
    }
    return syncResponses.removeAt(0);
  }
}

class SharedOtBackend {
  int _revision = 0;
  final List<Operation> _operations = [];

  SyncResponse sync({
    required String noteId,
    required String actorId,
    required SyncRequest request,
  }) {
    final accepted = <AcceptedOperation>[];
    for (final op in request.operations) {
      _revision++;
      _operations.add(
        Operation(
          operationId: op.operationId,
          noteId: noteId,
          revision: _revision,
          baseRevision: op.baseRevision,
          actorId: actorId,
          kind: op.kind,
          blockId: op.blockId,
          payload: op.payload,
          createdAt: DateTime.utc(2026, 7, 26),
        ),
      );
      accepted.add(
        AcceptedOperation(
          operationId: op.operationId,
          revision: _revision,
          kind: op.kind,
          blockId: op.blockId,
        ),
      );
    }
    return SyncResponse(
      accepted: accepted,
      finalRevision: _revision,
      remoteOperations: _operations
          .where((op) => op.revision > request.knownRevision)
          .toList(),
      canonicalDocument: _document(noteId),
      serverTime: DateTime.utc(2026, 7, 26),
    );
  }

  OperationsListResponse operationsSince(String noteId, int afterRevision) {
    final operations = _operations
        .where((op) => op.noteId == noteId && op.revision > afterRevision)
        .toList();
    if (operations.isEmpty) {
      return OperationsListResponse(operations: const []);
    }
    return OperationsListResponse(
      operations: operations,
      document: _document(noteId),
      revision: _revision,
    );
  }

  Map<String, dynamic> _document(String noteId) {
    final text = _operations
        .where((op) => op.noteId == noteId)
        .map(_operationLabel)
        .join(' ');
    return {
      'schemaVersion': 1,
      'blocks': [
        {
          'id': 'b1',
          'type': 'paragraph',
          'delta': [
            {'insert': text},
          ],
        },
      ],
    };
  }

  String _operationLabel(Operation op) {
    if (op.kind == 'complete_task_occurrence') {
      return [
        op.payload['taskId'],
        op.payload['scheduledAt'],
        op.payload['completedAt'] ?? 'reopened',
      ].join(':');
    }
    return op.payload['label'] as String? ?? op.operationId;
  }
}

class SharedBackendNoteSyncClient implements NoteSyncClient {
  SharedBackendNoteSyncClient({
    required this.backend,
    required this.actorId,
    this.online = true,
  });

  final SharedOtBackend backend;
  final String actorId;
  bool online;

  @override
  Future<NoteDocumentResponse> getDocument(String noteId) {
    throw UnimplementedError('getDocument is not used by these tests');
  }

  @override
  Future<NoteDocumentResponse?> fetchDocument(String noteId) {
    throw UnimplementedError('fetchDocument is not used by these tests');
  }

  @override
  Future<List<Map<String, dynamic>>> listNotes({
    int limit = 100,
    DateTime? cursorUpdatedAt,
    String? cursorId,
  }) {
    throw UnimplementedError('listNotes is not used by these tests');
  }

  @override
  Future<void> deleteNote(String noteId) {
    throw UnimplementedError('deleteNote is not used by these tests');
  }

  @override
  Future<OperationsListResponse> getOperationsSince(
    String noteId,
    int afterRevision,
  ) async {
    if (!online) throw StateError('offline');
    return backend.operationsSince(noteId, afterRevision);
  }

  @override
  Future<SyncResponse> syncOperations(
    String noteId,
    SyncRequest request,
  ) async {
    if (!online) throw StateError('offline');
    return backend.sync(noteId: noteId, actorId: actorId, request: request);
  }
}
