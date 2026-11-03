import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:appflowy_editor/appflowy_editor.dart' hide Operation;
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/notes/editor/appflowy/appflowy_note_adapter.dart';
import 'package:supanotes/features/notes/editor/appflowy/note_appflowy_codec.dart';
import 'package:supanotes/features/notes/editor/document/note_blocks.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supanotes/core/database/daos/note_operations_pending_query.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/sync/note_operations_sync_service.dart';
import 'package:supanotes/core/sync/note_outbox_worker.dart';
import 'package:supanotes/features/notes/editor/sync/note_sync_client.dart';
import 'package:supanotes/features/notes/editor/sync/note_sync_session.dart';

class _OfflineNoteSyncClient extends Mock implements NoteSyncClient {}

SyncResponse _acceptedResponse(SyncRequest request, String text) {
  final finalRevision = request.knownRevision + request.operations.length;
  return SyncResponse(
    accepted: [
      for (var i = 0; i < request.operations.length; i++)
        AcceptedOperation(
          operationId: request.operations[i].operationId,
          revision: request.knownRevision + i + 1,
          kind: request.operations[i].kind,
          blockId: request.operations[i].blockId,
        ),
    ],
    finalRevision: finalRevision,
    remoteOperations: const [],
    canonicalDocument: {
      'schemaVersion': 1,
      'blocks': [
        {
          'id': 'init',
          'type': 'paragraph',
          'delta': [
            {'insert': text},
          ],
        },
      ],
    },
    serverTime: DateTime.utc(2026, 9, 1),
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(
      SyncRequest(knownRevision: 0, operations: const [], clientId: 'fallback'),
    );
  });

  test(
    'session disposal projects an edit captured during the final flush',
    () async {
      final database = AppDatabase.test();
      final client = _OfflineNoteSyncClient();
      when(
        () => client.syncOperations(any(), any()),
      ).thenThrow(StateError('network unavailable'));
      final syncService = NoteOperationsSyncService(
        syncClient: client,
        dao: database.noteOperationsDao,
        clientId: 'client-1',
        actorId: 'user-1',
      );
      addTearDown(database.close);

      await database.notesDao.createNote(
        NotesCompanion.insert(
          id: 'close-note',
          userId: 'user-1',
          content: '',
          createdAt: DateTime.utc(2026, 7, 26),
          updatedAt: DateTime.utc(2026, 7, 26),
          hasRemoteCopy: const Value(false),
        ),
      );

      final editor = _editorState();
      final session = NoteSyncSession(
        noteId: 'close-note',
        syncService: syncService,
        adapter: AppFlowyNoteAdapter(
          editorState: editor,
          syncService: syncService,
          noteId: 'close-note',
          captureLocalOperations: false,
        ),
        captureLocalOperations: false,
      );

      await session.start();
      session.setCaptureLocalOperations(true);
      await _type(editor, 0, 'Última edição');
      await session.dispose();

      verifyNever(() => client.syncOperations(any(), any()));

      final localDocument = await database.noteOperationsDao
          .watchNoteDocument('close-note')
          .first;
      expect(
        jsonDecode(
          localDocument!.materializedDocumentJson!,
        )['blocks'][0]['delta'][0]['insert'],
        'Última edição',
      );
      editor.dispose();
    },
  );

  test(
    'restores a new note edit from the persisted outbox after restart offline',
    () async {
      final database = AppDatabase.test();
      final client = _OfflineNoteSyncClient();
      final syncService = NoteOperationsSyncService(
        syncClient: client,
        dao: database.noteOperationsDao,
        clientId: 'client-1',
        actorId: 'user-1',
      );
      addTearDown(database.close);

      final firstEditor = _editorState();
      final firstAdapter = AppFlowyNoteAdapter(
        editorState: firstEditor,
        syncService: syncService,
        noteId: 'offline-note',
      );

      await firstAdapter.start();
      await _type(firstEditor, 0, 'Rascunho offline');
      await firstAdapter.flushNow();
      firstAdapter.dispose();

      expect(
        await database.noteOperationsDao.getPendingOperations(
          'offline-note',
          ownerUserId: 'user-1',
        ),
        hasLength(1),
      );

      final restartedEditor = _editorState();
      final restartedAdapter = AppFlowyNoteAdapter(
        editorState: restartedEditor,
        syncService: syncService,
        noteId: 'offline-note',
      );
      addTearDown(restartedAdapter.dispose);

      await restartedAdapter.start();

      expect(
        _text(restartedEditor),
        'Rascunho offline',
      );
    },
  );

  test(
    'restores an edit after process death during an offline in-flight sync',
    () async {
      final database = AppDatabase.test();
      final client = _OfflineNoteSyncClient();
      when(
        () => client.syncOperations(any(), any()),
      ).thenThrow(StateError('network unavailable'));
      final syncService = NoteOperationsSyncService(
        syncClient: client,
        dao: database.noteOperationsDao,
        clientId: 'client-1',
        actorId: 'user-1',
      );
      addTearDown(database.close);

      final firstEditor = _editorState();
      final firstAdapter = AppFlowyNoteAdapter(
        editorState: firstEditor,
        syncService: syncService,
        noteId: 'in-flight-note',
      );

      await firstAdapter.start();
      await _type(firstEditor, 0, 'Edição durante queda');
      await firstAdapter.flushNow();

      await expectLater(
        syncService.syncPending('in-flight-note'),
        throwsA(isA<StateError>()),
      );
      expect(
        (await database.noteOperationsDao.getPendingOperations(
          'in-flight-note',
          ownerUserId: 'user-1',
        )).single.status,
        'in_flight',
      );
      firstAdapter.dispose();

      final restartedEditor = _editorState();
      final restartedAdapter = AppFlowyNoteAdapter(
        editorState: restartedEditor,
        syncService: syncService,
        noteId: 'in-flight-note',
      );
      addTearDown(restartedAdapter.dispose);

      await restartedAdapter.start();

      expect(
        _text(restartedEditor),
        'Edição durante queda',
      );
    },
  );

  test(
    'closed offline note is drained by the global outbox after reconnect',
    () async {
      final database = AppDatabase.test();
      final client = _OfflineNoteSyncClient();
      var online = false;
      final offlineAttempted = Completer<void>();

      when(() => client.syncOperations(any(), any()))
          .thenAnswer((invocation) async {
            if (!online) {
              if (!offlineAttempted.isCompleted) offlineAttempted.complete();
              throw NoteOperationsException(
                errorCode: 'NETWORK_ERROR',
                message: 'offline',
              );
            }
            final request = invocation.positionalArguments[1] as SyncRequest;
            return _acceptedResponse(request, 'Rascunho global');
          });

      final syncService = NoteOperationsSyncService(
        syncClient: client,
        dao: database.noteOperationsDao,
        clientId: 'client-1',
        actorId: 'user-1',
      );

      await database.notesDao.createNote(
        NotesCompanion.insert(
          id: 'global-outbox-note',
          userId: 'user-1',
          content: '',
          createdAt: DateTime.utc(2026, 9, 1),
          updatedAt: DateTime.utc(2026, 9, 1),
          hasRemoteCopy: const Value(false),
        ),
      );

      final editor = _editorState();
      final session = NoteSyncSession(
        noteId: 'global-outbox-note',
        syncService: syncService,
        adapter: AppFlowyNoteAdapter(
          editorState: editor,
          syncService: syncService,
          noteId: 'global-outbox-note',
          captureLocalOperations: false,
        ),
        captureLocalOperations: false,
        networkCoalescingWindow: const Duration(seconds: 5),
      );

      await session.start();
      session.setCaptureLocalOperations(true);
      await _type(editor, 0, 'Rascunho global');

      await session.flushNow();
      await offlineAttempted.future.timeout(const Duration(milliseconds: 500));
      await pumpEventQueue();
      await session.dispose();
      editor.dispose();

      final durableBeforeReconnect = await database.noteOperationsDao
          .getPendingOperations(
            'global-outbox-note',
            ownerUserId: 'user-1',
          );
      expect(durableBeforeReconnect, hasLength(1));
      expect(durableBeforeReconnect.single.status, 'in_flight');
      expect(
        await database.noteOperationsDao.getPendingNoteIds(
          ownerUserId: 'user-1',
        ),
        contains('global-outbox-note'),
      );

      online = true;
      final worker = NoteOutboxWorker(
        loadPendingNoteIds: () => database.noteOperationsDao.getPendingNoteIds(
          ownerUserId: 'user-1',
        ),
        syncNote: syncService.syncPending,
        isNoteActive: (_) => false,
      );
      addTearDown(worker.dispose);

      await worker.drain();

      expect(
        await database.noteOperationsDao.getPendingOperations(
          'global-outbox-note',
          ownerUserId: 'user-1',
        ),
        isEmpty,
      );
      final confirmed = await database.noteOperationsDao
          .watchNoteDocument('global-outbox-note')
          .first;
      expect(confirmed, isNotNull);
      expect(confirmed!.revision, 1);
      expect(
        jsonDecode(confirmed.documentJson)['blocks'][0]['delta'][0]['insert'],
        'Rascunho global',
      );

      await database.close();
    },
  );
}

EditorState _editorState() => EditorState(
  document: const NoteAppFlowyCodec().toDocument([
    NoteBlock(id: 'init', type: 'paragraph'),
  ]),
);

Future<void> _type(EditorState editorState, int offset, String text) =>
    editorState.apply(
      editorState.transaction
        ..insertText(editorState.getNodeAtPath([0])!, offset, text),
    );

String _text(EditorState editorState) =>
    editorState.getNodeAtPath([0])!.delta!.toPlainText();
