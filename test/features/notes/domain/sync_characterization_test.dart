import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:super_editor/super_editor.dart';

import 'package:supanotes/core/sync/note_operations_sync_service.dart';
import 'package:supanotes/features/notes/data/note_sync_client.dart';
import 'package:supanotes/features/notes/domain/note_sync_session.dart';

class MockSyncService extends Mock implements NoteOperationsSyncService {}

class FakeOperationRequest extends Fake implements OperationRequest {}

void main() {
  late MockSyncService mockSyncService;
  late MutableDocument document;
  late MutableDocumentComposer composer;
  late Editor editor;

  setUpAll(() {
    registerFallbackValue(FakeOperationRequest());
    registerFallbackValue('note-characterization-1');
  });

  setUp(() {
    mockSyncService = MockSyncService();
    document = MutableDocument(
      nodes: [ParagraphNode(id: 'block-1', text: AttributedText('Initial text'))],
    );
    composer = MutableDocumentComposer();
    editor = createDefaultDocumentEditor(
      document: document,
      composer: composer,
    );

    when(() => mockSyncService.generateOperationId()).thenReturn('op-id-1');
    when(
      () => mockSyncService.getConfirmedDocument(any()),
    ).thenAnswer((_) async => null);
    when(
      () => mockSyncService.enqueueOperation(any(), any()),
    ).thenAnswer((_) async {});
    when(
      () => mockSyncService.getPendingOperations(any()),
    ).thenAnswer((_) async => []);
    when(
      () => mockSyncService.getProjectedOutboxOperationCount(any()),
    ).thenAnswer((_) async => 0);
    when(
      () => mockSyncService.fetchDocument(any()),
    ).thenAnswer((_) async => null);
    when(
      () => mockSyncService.loadPendingProjection(any()),
    ).thenAnswer((_) async => []);
    when(
      () => mockSyncService.syncPending(any(), onReconcile: any(named: 'onReconcile')),
    ).thenAnswer((_) async => SyncResult.empty());
    when(
      () => mockSyncService.pollAndReconcile(any(), onReconcile: any(named: 'onReconcile')),
    ).thenAnswer((_) async => SyncResult.empty());
  });

  test('NoteSyncSession lifecycle: start, track active state, and dispose', () async {
    const noteId = 'note-characterization-1';
    expect(NoteSyncSession.isActive(noteId), isFalse);

    final session = NoteSyncSession(
      noteId: noteId,
      syncService: mockSyncService,
      document: document,
      editor: editor,
    );

    await session.start();
    expect(NoteSyncSession.isActive(noteId), isTrue);

    await session.dispose();
    expect(NoteSyncSession.isActive(noteId), isFalse);
  });

  test('Local text edit captures single operation request', () async {
    const noteId = 'note-characterization-1';
    final session = NoteSyncSession(
      noteId: noteId,
      syncService: mockSyncService,
      document: document,
      editor: editor,
    );

    await session.start();

    // Perform an edit in SuperEditor
    editor.execute([
      InsertTextRequest(
        documentPosition: DocumentPosition(
          nodeId: 'block-1',
          nodePosition: const TextNodePosition(offset: 12),
        ),
        textToInsert: ' updated',
        attributions: const {},
      ),
    ]);

    await session.flushNow();

    verify(
      () => mockSyncService.enqueueOperation(noteId, any()),
    ).called(greaterThanOrEqualTo(1));

    await session.dispose();
  });

  test('Editing inside 50ms debounce and calling dispose flushes outbox and syncs pending ops', () async {
    const noteId = 'note-characterization-dispose-flush';
    final session = NoteSyncSession(
      noteId: noteId,
      syncService: mockSyncService,
      document: document,
      editor: editor,
    );

    await session.start();
    clearInteractions(mockSyncService);

    // Perform an edit within the 50ms debounce window
    editor.execute([
      InsertTextRequest(
        documentPosition: DocumentPosition(
          nodeId: 'block-1',
          nodePosition: const TextNodePosition(offset: 12),
        ),
        textToInsert: ' quick edit',
        attributions: const {},
      ),
    ]);

    // Call dispose() immediately without waiting for the 50ms debounce timer
    await session.dispose();

    // Confirm that debounced edit was flushed to outbox AND syncPending was triggered (once via onLocalOperations and once via dispose sync)
    verify(() => mockSyncService.enqueueOperation(noteId, any())).called(1);
    verify(() => mockSyncService.syncPending(noteId, onReconcile: any(named: 'onReconcile'))).called(1);
    expect(NoteSyncSession.isActive(noteId), isFalse);
  });

  test('Re-opening a note while old session dispose is in flight preserves new session active state', () async {
    const noteId = 'note-reopen-test';
    final session1 = NoteSyncSession(
      noteId: noteId,
      syncService: mockSyncService,
      document: document,
      editor: editor,
    );
    await session1.start();
    expect(NoteSyncSession.isActive(noteId), isTrue);

    final syncCompleter = Completer<SyncResult>();
    var delaySync = false;
    when(
      () => mockSyncService.syncPending(noteId, onReconcile: any(named: 'onReconcile')),
    ).thenAnswer((_) {
      if (delaySync) {
        delaySync = false;
        return syncCompleter.future;
      }
      return Future.value(SyncResult.empty());
    });

    // Start dispose on session1 while syncPending is delayed
    delaySync = true;
    final disposeFuture = session1.dispose();

    // Immediately start session2 for the same noteId
    final session2 = NoteSyncSession(
      noteId: noteId,
      syncService: mockSyncService,
      document: document,
      editor: editor,
    );
    await session2.start();

    // Complete session1's syncPending
    syncCompleter.complete(SyncResult.empty());
    await disposeFuture;

    // session2 must still be active!
    expect(NoteSyncSession.isActive(noteId), isTrue);

    await session2.dispose();
    expect(NoteSyncSession.isActive(noteId), isFalse);
  });
}
