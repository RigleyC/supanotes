import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:super_editor/super_editor.dart';

import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/sync/note_operations_sync_service.dart';
import 'package:supanotes/features/notes/editor/sync/note_operation_adapter.dart';
import 'package:supanotes/features/notes/editor/sync/note_sync_client.dart';

class _OfflineNoteSyncClient extends Mock implements NoteSyncClient {}

void main() {
  setUpAll(() {
    registerFallbackValue(
      SyncRequest(knownRevision: 0, operations: const [], clientId: 'fallback'),
    );
  });

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
