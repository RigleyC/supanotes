import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/sync/note_operations_sync_service.dart';
import 'package:supanotes/features/notes/editor/sync/note_sync_client.dart';

class _MockNoteSyncClient extends Mock implements NoteSyncClient {}

void main() {
  setUpAll(() {
    registerFallbackValue(
      SyncRequest(knownRevision: 0, operations: const [], clientId: 'fallback'),
    );
  });

  test('successful sync keeps canonical plus newly pending ops materialized', () async {
    final db = AppDatabase.test();
    addTearDown(db.close);
    final client = _MockNoteSyncClient();
    final requestStarted = Completer<SyncRequest>();
    final releaseResponse = Completer<SyncResponse>();
    when(() => client.syncOperations(any(), any())).thenAnswer((invocation) {
      final request = invocation.positionalArguments[1] as SyncRequest;
      if (!requestStarted.isCompleted) requestStarted.complete(request);
      return releaseResponse.future;
    });

    await db.notesDao.createNote(
      NotesCompanion.insert(
        id: 'projection-note',
        userId: 'user-1',
        content: 'base',
        createdAt: DateTime.utc(2026, 9, 2),
        updatedAt: DateTime.utc(2026, 9, 2),
        hasRemoteCopy: const Value(true),
      ),
    );
    const baseDocument = {
      'schemaVersion': 1,
      'blocks': [
        {
          'id': 'base',
          'type': 'paragraph',
          'delta': [
            {'insert': 'base'},
          ],
        },
      ],
    };
    await db.noteOperationsDao.upsertNoteDocument(
      LocalNoteDocumentsCompanion.insert(
        noteId: 'projection-note',
        revision: 0,
        documentJson: NoteOperationsSyncService.encodeDocument(baseDocument),
        updatedAt: DateTime.utc(2026, 9, 2),
        materializedDocumentJson: Value(
          NoteOperationsSyncService.encodeDocument(baseDocument),
        ),
      ),
    );

    final service = NoteOperationsSyncService(
      syncClient: client,
      dao: db.noteOperationsDao,
      clientId: 'client-1',
      actorId: 'user-1',
    );
    await service.enqueueOperation(
      'projection-note',
      OperationRequest(
        operationId: 'op-accepted',
        baseRevision: 0,
        kind: 'create_block',
        payload: const {
          'id': 'accepted',
          'type': 'paragraph',
          'afterBlockId': 'base',
          'delta': [
            {'insert': 'accepted'},
          ],
        },
      ),
    );

    final sync = service.syncPending('projection-note');
    final sent = await requestStarted.future;

    await service.enqueueOperation(
      'projection-note',
      OperationRequest(
        operationId: 'op-pending',
        baseRevision: 1,
        kind: 'create_block',
        payload: const {
          'id': 'pending',
          'type': 'paragraph',
          'afterBlockId': 'accepted',
          'delta': [
            {'insert': 'pending-local'},
          ],
        },
      ),
    );

    releaseResponse.complete(
      SyncResponse(
        accepted: [
          AcceptedOperation(
            operationId: sent.operations.single.operationId,
            revision: 1,
            kind: 'create_block',
          ),
        ],
        finalRevision: 1,
        remoteOperations: const [],
        canonicalDocument: const {
          'schemaVersion': 1,
          'blocks': [
            {
              'id': 'base',
              'type': 'paragraph',
              'delta': [
                {'insert': 'base'},
              ],
            },
            {
              'id': 'accepted',
              'type': 'paragraph',
              'delta': [
                {'insert': 'accepted'},
              ],
            },
          ],
        },
        serverTime: DateTime.utc(2026, 9, 2, 12),
      ),
    );
    await sync;

    final stored = await db.noteOperationsDao.watchNoteDocument('projection-note').first;
    expect(stored, isNotNull);
    expect(stored!.documentJson, isNot(contains('pending-local')));
    expect(stored.materializedDocumentJson, contains('pending-local'));
    final pending = await service.getPendingOperations('projection-note');
    expect(pending.map((op) => op.operationId), contains('op-pending'));
  });
}
