import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';
import 'package:mocktail/mocktail.dart';
import 'package:super_editor/super_editor.dart';

import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/sync/note_operations_sync_service.dart';
import 'package:supanotes/features/notes/editor/sync/note_operation_adapter.dart';
import 'package:supanotes/features/notes/editor/sync/note_sync_client.dart';
import 'package:supanotes/features/notes/editor/sync/note_sync_session.dart';
import 'package:supanotes/features/tasks/domain/task_projection_engine.dart';

class _OfflineNoteSyncClient extends Mock implements NoteSyncClient {}

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

      final document = MutableDocument(
        nodes: [ParagraphNode(id: 'init', text: AttributedText())],
      );
      final editor = createDefaultDocumentEditor(
        document: document,
        composer: MutableDocumentComposer(),
      );
      final session = NoteSyncSession(
        noteId: 'close-note',
        syncService: syncService,
        document: document,
        editor: editor,
        taskProjectionEngine: TaskProjectionEngine(database: database),
        userId: 'user-1',
        captureLocalOperations: false,
      );

      await session.start();
      session.setCaptureLocalOperations(true);
      editor.execute([
        InsertTextRequest(
          documentPosition: const DocumentPosition(
            nodeId: 'init',
            nodePosition: TextNodePosition(offset: 0),
          ),
          textToInsert: 'Última edição',
          attributions: const {},
        ),
      ]);
      await session.dispose();

      verifyNever(() => client.syncOperations(any(), any()));

      expect(
        (await database.notesDao.getNoteById('close-note'))!.content,
        'Última edição',
      );
      editor.dispose();
      document.dispose();
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

      final firstDocument = MutableDocument(
        nodes: [ParagraphNode(id: 'init', text: AttributedText())],
      );
      final firstEditor = createDefaultDocumentEditor(
        document: firstDocument,
        composer: MutableDocumentComposer(),
      );
      final firstAdapter = NoteOperationAdapter(
        document: firstDocument,
        syncService: syncService,
        noteId: 'offline-note',
        editor: firstEditor,
      );

      await firstAdapter.start();
      firstEditor.execute([
        InsertTextRequest(
          documentPosition: const DocumentPosition(
            nodeId: 'init',
            nodePosition: TextNodePosition(offset: 0),
          ),
          textToInsert: 'Rascunho offline',
          attributions: const {},
        ),
      ]);
      await firstAdapter.flushNow();
      firstAdapter.dispose();

      expect(
        await database.noteOperationsDao.getPendingOperations(
          'offline-note',
          ownerUserId: 'user-1',
        ),
        hasLength(1),
      );

      final restartedDocument = MutableDocument(
        nodes: [ParagraphNode(id: 'init', text: AttributedText())],
      );
      final restartedEditor = createDefaultDocumentEditor(
        document: restartedDocument,
        composer: MutableDocumentComposer(),
      );
      final restartedAdapter = NoteOperationAdapter(
        document: restartedDocument,
        syncService: syncService,
        noteId: 'offline-note',
        editor: restartedEditor,
      );
      addTearDown(restartedAdapter.dispose);

      await restartedAdapter.start();

      expect(
        (restartedDocument.first as TextNode).text.toPlainText(),
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

      final firstDocument = MutableDocument(
        nodes: [ParagraphNode(id: 'init', text: AttributedText())],
      );
      final firstEditor = createDefaultDocumentEditor(
        document: firstDocument,
        composer: MutableDocumentComposer(),
      );
      final firstAdapter = NoteOperationAdapter(
        document: firstDocument,
        syncService: syncService,
        noteId: 'in-flight-note',
        editor: firstEditor,
      );

      await firstAdapter.start();
      firstEditor.execute([
        InsertTextRequest(
          documentPosition: const DocumentPosition(
            nodeId: 'init',
            nodePosition: TextNodePosition(offset: 0),
          ),
          textToInsert: 'Edição durante queda',
          attributions: const {},
        ),
      ]);
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

      final restartedDocument = MutableDocument(
        nodes: [ParagraphNode(id: 'init', text: AttributedText())],
      );
      final restartedEditor = createDefaultDocumentEditor(
        document: restartedDocument,
        composer: MutableDocumentComposer(),
      );
      final restartedAdapter = NoteOperationAdapter(
        document: restartedDocument,
        syncService: syncService,
        noteId: 'in-flight-note',
        editor: restartedEditor,
      );
      addTearDown(restartedAdapter.dispose);

      await restartedAdapter.start();

      expect(
        (restartedDocument.first as TextNode).text.toPlainText(),
        'Edição durante queda',
      );
    },
  );
}
