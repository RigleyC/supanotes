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
  Future<List<Map<String, dynamic>>> listNotes() {
    throw UnimplementedError('listNotes is not used by these tests');
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

  @override
  bool isNoteActiveLocally(String noteId) => false;
}
