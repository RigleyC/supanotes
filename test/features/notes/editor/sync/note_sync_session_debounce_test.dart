import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/sync/note_operations_sync_service.dart';
import 'package:supanotes/features/notes/editor/sync/note_sync_client.dart';
import 'package:supanotes/features/notes/editor/sync/note_sync_session.dart';
import 'package:super_editor/super_editor.dart';

class _MockNoteSyncClient extends Mock implements NoteSyncClient {}

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

  test('multiple local flushes inside the window produce one network sync', () async {
    final database = AppDatabase.test();
    final client = _MockNoteSyncClient();
    var networkCalls = 0;
    when(() => client.syncOperations(any(), any())).thenAnswer((invocation) async {
      networkCalls++;
      final request = invocation.positionalArguments[1] as SyncRequest;
      return _acceptedResponse(request, 'ab');
    });

    final syncService = NoteOperationsSyncService(
      syncClient: client,
      dao: database.noteOperationsDao,
      clientId: 'client-1',
      actorId: 'user-1',
    );
    final document = MutableDocument(
      nodes: [ParagraphNode(id: 'init', text: AttributedText())],
    );
    final editor = createDefaultDocumentEditor(
      document: document,
      composer: MutableDocumentComposer(),
    );
    final session = NoteSyncSession(
      noteId: 'debounce-note',
      syncService: syncService,
      document: document,
      editor: editor,
      userId: 'user-1',
      captureLocalOperations: false,
      networkCoalescingWindow: const Duration(milliseconds: 300),
    );
    addTearDown(() async {
      await session.dispose();
      editor.dispose();
      document.dispose();
      await database.close();
    });

    await session.start();
    session.setCaptureLocalOperations(true);

    editor.execute([
      InsertTextRequest(
        documentPosition: const DocumentPosition(
          nodeId: 'init',
          nodePosition: TextNodePosition(offset: 0),
        ),
        textToInsert: 'a',
        attributions: const {},
      ),
    ]);
    await Future<void>.delayed(const Duration(milliseconds: 80));

    editor.execute([
      InsertTextRequest(
        documentPosition: const DocumentPosition(
          nodeId: 'init',
          nodePosition: TextNodePosition(offset: 1),
        ),
        textToInsert: 'b',
        attributions: const {},
      ),
    ]);
    await Future<void>.delayed(const Duration(milliseconds: 180));

    expect(networkCalls, 0);

    await Future<void>.delayed(const Duration(milliseconds: 220));
    expect(networkCalls, 1);
  });

  test('flushNow guarantees local durability without waiting for remote ack', () async {
    final database = AppDatabase.test();
    final client = _MockNoteSyncClient();
    final remoteRelease = Completer<SyncResponse>();
    when(
      () => client.syncOperations(any(), any()),
    ).thenAnswer((_) => remoteRelease.future);

    final syncService = NoteOperationsSyncService(
      syncClient: client,
      dao: database.noteOperationsDao,
      clientId: 'client-1',
      actorId: 'user-1',
    );
    final document = MutableDocument(
      nodes: [ParagraphNode(id: 'init', text: AttributedText())],
    );
    final editor = createDefaultDocumentEditor(
      document: document,
      composer: MutableDocumentComposer(),
    );
    final session = NoteSyncSession(
      noteId: 'flush-note',
      syncService: syncService,
      document: document,
      editor: editor,
      userId: 'user-1',
      captureLocalOperations: false,
      networkCoalescingWindow: const Duration(seconds: 5),
    );

    await session.start();
    session.setCaptureLocalOperations(true);
    editor.execute([
      InsertTextRequest(
        documentPosition: const DocumentPosition(
          nodeId: 'init',
          nodePosition: TextNodePosition(offset: 0),
        ),
        textToInsert: 'durable',
        attributions: const {},
      ),
    ]);

    await session.flushNow().timeout(const Duration(milliseconds: 250));

    final pending = await database.noteOperationsDao.getPendingOperations(
      'flush-note',
      ownerUserId: 'user-1',
    );
    expect(pending, hasLength(1));

    final capturedRequest = verify(
      () => client.syncOperations('flush-note', captureAny()),
    ).captured.single as SyncRequest;
    remoteRelease.complete(_acceptedResponse(capturedRequest, 'durable'));
    await pumpEventQueue();

    await session.dispose();
    editor.dispose();
    document.dispose();
    await database.close();
  });
}
