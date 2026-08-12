import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:super_editor/super_editor.dart';

import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/sync/note_operations_sync_service.dart';
import 'package:supanotes/features/notes/editor/sync/note_sync_client.dart';
import 'package:supanotes/features/notes/editor/sync/note_session_handle.dart';
import 'package:supanotes/features/notes/editor/sync/note_sync_session.dart';
import 'package:supanotes/features/tasks/domain/task_projection_engine.dart';

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
      nodes: [
        ParagraphNode(id: 'block-1', text: AttributedText('Initial text')),
      ],
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
      () => mockSyncService.enqueueOperations(any(), any()),
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
      () => mockSyncService.syncPending(
        any(),
        onReconcile: any(named: 'onReconcile'),
      ),
    ).thenAnswer((_) async => SyncResult.empty());
    when(
      () => mockSyncService.pollAndReconcile(
        any(),
        onReconcile: any(named: 'onReconcile'),
      ),
    ).thenAnswer((_) async => SyncResult.empty());
  });

  test('does not resume session startup after disposal', () async {
    const noteId = 'note-dispose-during-start';
    final confirmedDocument = Completer<LocalNoteDocumentData?>();
    when(
      () => mockSyncService.getConfirmedDocument(noteId),
    ).thenAnswer((_) => confirmedDocument.future);

    final session = NoteSyncSession(
      noteId: noteId,
      syncService: mockSyncService,
      document: document,
      editor: editor,
    );
    final startFuture = session.start();
    await Future<void>.delayed(Duration.zero);

    final disposeFuture = session.dispose();
    confirmedDocument.complete(null);
    await Future.wait([startFuture, disposeFuture]);

    verifyNever(
      () => mockSyncService.syncPending(
        noteId,
        onReconcile: any(named: 'onReconcile'),
      ),
    );
    verifyNever(
      () => mockSyncService.pollAndReconcile(
        noteId,
        onReconcile: any(named: 'onReconcile'),
      ),
    );
    expect(session.status, NoteSessionStatus.closed);
  });

  test('opens from local state before a slow network sync completes', () async {
    const noteId = 'note-local-first-opening';
    final syncCompleter = Completer<SyncResult>();
    when(() => mockSyncService.getConfirmedDocument(noteId)).thenAnswer(
      (_) async => LocalNoteDocumentData(
        noteId: noteId,
        revision: 4,
        documentJson:
            '{"blocks":[{"id":"local-block","type":"paragraph","delta":[{"insert":"Conteudo local"}],"metadata":{}}]}',
        updatedAt: DateTime.utc(2026, 8, 3),
      ),
    );
    var syncStarted = false;
    when(
      () => mockSyncService.syncPending(
        noteId,
        onReconcile: any(named: 'onReconcile'),
      ),
    ).thenAnswer((_) {
      syncStarted = true;
      return syncCompleter.future;
    });

    var startCompleted = false;
    final session = NoteSyncSession(
      noteId: noteId,
      syncService: mockSyncService,
      document: document,
      editor: editor,
    );
    final startFuture = session.start().then((_) {
      startCompleted = true;
    });

    try {
      await pumpEventQueue();

      expect(startCompleted, isTrue);
      expect(syncStarted, isTrue);
      expect((document.first as TextNode).text.toPlainText(), 'Conteudo local');
    } finally {
      if (!syncCompleter.isCompleted) {
        syncCompleter.complete(SyncResult.empty());
      }
      await startFuture;
      await session.dispose();
    }
  });

  test('marks the session ready before task projection completes', () async {
    const noteId = 'note-local-first-projection';
    final projectionDb = AppDatabase.test();
    final projection = GateTaskProjectionEngine(database: projectionDb);
    final session = NoteSyncSession(
      noteId: noteId,
      syncService: mockSyncService,
      document: document,
      editor: editor,
      taskProjectionEngine: projection,
      userId: 'user-1',
    );
    var startCompleted = false;
    final startFuture = session.start().then((_) {
      startCompleted = true;
    });

    try {
      await projection.started.future.timeout(const Duration(seconds: 1));
      await pumpEventQueue();

      expect(startCompleted, isTrue);
      expect(session.status, NoteSessionStatus.ready);
    } finally {
      if (!projection.release.isCompleted) {
        projection.release.complete();
      }
      await startFuture;
      await session.dispose();
      await projectionDb.close();
    }
  });

  test('keeps the session open when the final projection fails', () async {
    const noteId = 'note-projection-failure';
    final projectionDb = AppDatabase.test();
    final projection = FailingTaskProjectionEngine(
      database: projectionDb,
      failuresRemaining: 2,
    );
    final session = NoteSyncSession(
      noteId: noteId,
      syncService: mockSyncService,
      document: document,
      editor: editor,
      taskProjectionEngine: projection,
      userId: 'user-1',
    );

    await session.start();
    await pumpEventQueue();
    editor.execute([
      InsertTextRequest(
        documentPosition: const DocumentPosition(
          nodeId: 'block-1',
          nodePosition: TextNodePosition(offset: 12),
        ),
        textToInsert: ' pending projection',
        attributions: const {},
      ),
    ]);

    await expectLater(session.dispose(), throwsA(isA<StateError>()));
    expect(session.status, NoteSessionStatus.syncError);

    projection.failuresRemaining = 0;
    await session.dispose();
    expect(session.status, NoteSessionStatus.closed);
    await projectionDb.close();
  });

  test(
    'persists a new edit before waiting for a slow sync during close',
    () async {
      const noteId = 'note-local-first-close';
      final syncCompleter = Completer<SyncResult>();
      final syncStartedCompleter = Completer<void>();
      var enqueued = false;
      when(
        () => mockSyncService.syncPending(
          noteId,
          onReconcile: any(named: 'onReconcile'),
        ),
      ).thenAnswer((_) {
        if (!syncStartedCompleter.isCompleted) {
          syncStartedCompleter.complete();
        }
        return syncCompleter.future;
      });
      when(() => mockSyncService.enqueueOperations(noteId, any())).thenAnswer((
        _,
      ) async {
        enqueued = true;
      });

      final session = NoteSyncSession(
        noteId: noteId,
        syncService: mockSyncService,
        document: document,
        editor: editor,
      );
      final startFuture = session.start();
      Future<void>? disposeFuture;
      var disposeCompleted = false;
      try {
        await syncStartedCompleter.future;
        editor.execute([
          InsertTextRequest(
            documentPosition: const DocumentPosition(
              nodeId: 'block-1',
              nodePosition: TextNodePosition(offset: 12),
            ),
            textToInsert: ' offline',
            attributions: const {},
          ),
        ]);

        disposeFuture = session.dispose();
        await pumpEventQueue();
        expect(enqueued, isTrue);
        await disposeFuture.timeout(const Duration(seconds: 1));
        disposeCompleted = true;
        expect(syncCompleter.isCompleted, isFalse);
      } finally {
        if (!syncCompleter.isCompleted) {
          syncCompleter.complete(SyncResult.empty());
        }
        await startFuture;
        if (!disposeCompleted) {
          disposeFuture ??= session.dispose();
          await disposeFuture;
        }
      }
    },
  );

  test(
    'NoteSyncSession lifecycle starts sync resources and disposes them',
    () async {
      const noteId = 'note-characterization-1';

      final session = NoteSyncSession(
        noteId: noteId,
        syncService: mockSyncService,
        document: document,
        editor: editor,
      );

      await session.start();
      await pumpEventQueue();
      verify(
        () => mockSyncService.getConfirmedDocument(noteId),
      ).called(greaterThanOrEqualTo(1));
      verify(
        () => mockSyncService.syncPending(
          noteId,
          onReconcile: any(named: 'onReconcile'),
        ),
      ).called(greaterThanOrEqualTo(1));

      await session.dispose();
    },
  );

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
      () => mockSyncService.enqueueOperations(noteId, any()),
    ).called(greaterThanOrEqualTo(1));

    await session.dispose();
  });

  test(
    'Editing inside 50ms debounce and calling dispose flushes the outbox',
    () async {
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

      // Confirm that the debounced edit was flushed to the durable outbox.
      verify(() => mockSyncService.enqueueOperations(noteId, any())).called(1);
      verifyNever(
        () => mockSyncService.syncPending(
          noteId,
          onReconcile: any(named: 'onReconcile'),
        ),
      );
    },
  );

  test(
    'a failed close keeps the session and edit available for retry',
    () async {
      const noteId = 'note-retry-close';
      var enqueueAttempts = 0;
      when(() => mockSyncService.enqueueOperations(noteId, any())).thenAnswer((
        _,
      ) async {
        enqueueAttempts++;
        if (enqueueAttempts == 1) throw StateError('outbox unavailable');
      });

      final session = NoteSyncSession(
        noteId: noteId,
        syncService: mockSyncService,
        document: document,
        editor: editor,
      );
      await session.start();
      clearInteractions(mockSyncService);

      editor.execute([
        InsertTextRequest(
          documentPosition: const DocumentPosition(
            nodeId: 'block-1',
            nodePosition: TextNodePosition(offset: 12),
          ),
          textToInsert: ' retry close',
          attributions: const {},
        ),
      ]);

      await expectLater(session.dispose(), throwsA(isA<StateError>()));
      expect(session.status, NoteSessionStatus.syncError);

      await session.dispose();

      expect(enqueueAttempts, 2);
      expect(session.status, NoteSessionStatus.closed);
    },
  );

  test(
    'Delayed dispose reconciliation does not affect a newer direct session',
    () async {
      const noteId = 'note-reopen-test';
      final session1 = NoteSyncSession(
        noteId: noteId,
        syncService: mockSyncService,
        document: document,
        editor: editor,
      );
      await session1.start();

      final syncCompleter = Completer<SyncResult>();
      var delaySync = false;
      when(
        () => mockSyncService.syncPending(
          noteId,
          onReconcile: any(named: 'onReconcile'),
        ),
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

      verify(
        () => mockSyncService.getConfirmedDocument(noteId),
      ).called(greaterThanOrEqualTo(1));

      await session2.dispose();
    },
  );

  test(
    'Logout-like dispose prevents delayed reconciliation from projecting old user work',
    () async {
      const noteId = 'note-logout-dispose';
      final projectionDb = AppDatabase.test();
      final projection = RecordingTaskProjectionEngine(database: projectionDb);
      final session = NoteSyncSession(
        noteId: noteId,
        syncService: mockSyncService,
        document: document,
        editor: editor,
        taskProjectionEngine: projection,
        userId: 'user-old',
      );

      await session.start();
      await pumpEventQueue();
      expect(projection.userIds, contains('user-old'));
      projection.userIds.clear();

      final syncCompleter = Completer<SyncResult>();
      when(
        () => mockSyncService.syncPending(
          noteId,
          onReconcile: any(named: 'onReconcile'),
        ),
      ).thenAnswer((invocation) async {
        final result = await syncCompleter.future;
        final callback =
            invocation.namedArguments[#onReconcile]
                as Future<void> Function(SyncResult)?;
        if (callback != null) {
          await callback(result);
        }
        return result;
      });

      final disposeFuture = session.dispose();
      syncCompleter.complete(
        SyncResult(
          acceptedCount: 0,
          acceptedOperationIds: const [],
          finalRevision: 2,
          remoteOperations: const [],
          canonicalDocument: NoteDocumentResponse(
            noteId: noteId,
            revision: 2,
            document: const {'schemaVersion': 1, 'blocks': []},
            serverTime: DateTime.utc(2026, 7, 26),
          ),
        ),
      );

      await disposeFuture;

      expect(projection.userIds, isEmpty);
      await projectionDb.close();
    },
  );

  test(
    'View session receives remote polling updates without emitting mutations',
    () async {
      const noteId = 'note-view-shared';
      final session = NoteSyncSession(
        noteId: noteId,
        syncService: mockSyncService,
        document: document,
        editor: editor,
        captureLocalOperations: false,
      );
      final remoteResult = SyncResult(
        acceptedCount: 0,
        acceptedOperationIds: const [],
        finalRevision: 2,
        remoteOperations: [
          Operation(
            operationId: 'remote-op',
            noteId: noteId,
            revision: 2,
            baseRevision: 1,
            actorId: 'editor-user',
            kind: 'text_delta',
            blockId: 'block-1',
            payload: const {
              'ops': [
                {'retain': 12},
                {'insert': ' from editor-user'},
              ],
            },
            createdAt: DateTime.utc(2026, 7, 26),
          ),
        ],
        canonicalDocument: NoteDocumentResponse(
          noteId: noteId,
          revision: 2,
          document: const {
            'schemaVersion': 1,
            'blocks': [
              {
                'id': 'block-1',
                'type': 'paragraph',
                'delta': [
                  {'insert': 'Remote visible'},
                ],
              },
            ],
          },
          serverTime: DateTime.utc(2026, 7, 26),
        ),
      );
      when(
        () => mockSyncService.pollAndReconcile(
          noteId,
          onReconcile: any(named: 'onReconcile'),
        ),
      ).thenAnswer((invocation) async {
        final callback =
            invocation.namedArguments[#onReconcile]
                as Future<void> Function(SyncResult)?;
        if (callback != null) {
          await callback(remoteResult);
        }
        return remoteResult;
      });

      await session.start();
      clearInteractions(mockSyncService);

      editor.execute([
        InsertTextRequest(
          documentPosition: DocumentPosition(
            nodeId: 'block-1',
            nodePosition: const TextNodePosition(offset: 12),
          ),
          textToInsert: ' local view edit',
          attributions: const {},
        ),
      ]);
      await session.flushNow();
      await session.pollNow();

      final node = document.getNodeAt(0)! as TextNode;
      expect(node.text.toPlainText(), 'Remote visible');
      verifyNever(() => mockSyncService.enqueueOperations(noteId, any()));
      verifyNever(
        () => mockSyncService.syncPending(
          noteId,
          onReconcile: any(named: 'onReconcile'),
        ),
      );

      await session.dispose();
    },
  );

  test('transient sync errors do not become protocol errors', () async {
    const noteId = 'note-transient-error';
    final syncErrors = <Object>[];
    final protocolErrors = <Object>[];
    var readyCalls = 0;
    final session = NoteSyncSession(
      noteId: noteId,
      syncService: mockSyncService,
      document: document,
      editor: editor,
      onTransientError: syncErrors.add,
      onProtocolError: protocolErrors.add,
    );

    await session.start();
    final readyCallsAfterStart = readyCalls;
    when(
      () => mockSyncService.pollAndReconcile(
        noteId,
        onReconcile: any(named: 'onReconcile'),
      ),
    ).thenThrow(Exception('socket closed'));

    await session.pollNow();

    expect(syncErrors, hasLength(1));
    expect(protocolErrors, isEmpty);
    expect(readyCalls, readyCallsAfterStart);

    await session.dispose();
  });

  test('protocol sync errors are reported as protocol errors', () async {
    const noteId = 'note-protocol-error';
    final protocolErrors = <Object>[];
    final session = NoteSyncSession(
      noteId: noteId,
      syncService: mockSyncService,
      document: document,
      editor: editor,
      onProtocolError: protocolErrors.add,
    );

    await session.start();
    when(
      () => mockSyncService.pollAndReconcile(
        noteId,
        onReconcile: any(named: 'onReconcile'),
      ),
    ).thenThrow(StateError('protocol mismatch'));

    await session.pollNow();

    expect(protocolErrors, hasLength(1));
    await session.pollNow();
    verify(
      () => mockSyncService.pollAndReconcile(
        noteId,
        onReconcile: any(named: 'onReconcile'),
      ),
    ).called(1);

    await session.dispose();
  });

  test(
    'forbidden sync disables local capture after access is revoked',
    () async {
      const noteId = 'note-revoked-access';
      final session = NoteSyncSession(
        noteId: noteId,
        syncService: mockSyncService,
        document: document,
        editor: editor,
      );
      await session.start();
      when(
        () => mockSyncService.syncPending(
          noteId,
          onReconcile: any(named: 'onReconcile'),
        ),
      ).thenThrow(
        NoteOperationsException(
          errorCode: 'FORBIDDEN',
          message: 'access revoked',
          statusCode: 403,
        ),
      );

      await session.pollNow();

      expect(session.captureLocalOperations, isFalse);
      await session.dispose();
    },
  );

  test(
    'overlapping sync requests stay syncing until the queue drains',
    () async {
      const noteId = 'note-overlapping-status';
      final events = <String>[];
      final firstSync = Completer<SyncResult>();
      var calls = 0;
      when(
        () => mockSyncService.syncPending(
          noteId,
          onReconcile: any(named: 'onReconcile'),
        ),
      ).thenAnswer((_) {
        calls++;
        if (calls == 2) return firstSync.future;
        return Future.value(SyncResult.empty());
      });
      final session = NoteSyncSession(
        noteId: noteId,
        syncService: mockSyncService,
        document: document,
        editor: editor,
      );
      session.statusChanges.listen((status) => events.add(status.name));

      await session.start();
      events.clear();
      session.adapter.onLocalOperations?.call(const []);
      session.adapter.onLocalOperations?.call(const []);
      await pumpEventQueue();

      expect(events.where((e) => e == 'syncing').toList(), ['syncing']);
      firstSync.complete(SyncResult.empty());
      await pumpEventQueue();
      expect(events.last, 'ready');

      await session.dispose();
    },
  );

  test('task projections for one session never overlap', () async {
    const noteId = 'note-serialized-projection';
    final projectionDb = AppDatabase.test();
    final projection = BlockingTaskProjectionEngine(database: projectionDb);
    final session = NoteSyncSession(
      noteId: noteId,
      syncService: mockSyncService,
      document: document,
      editor: editor,
      taskProjectionEngine: projection,
      userId: 'user-1',
    );

    await session.start();
    session.adapter.onLocalOperations?.call(const []);
    session.adapter.onLocalOperations?.call(const []);
    await pumpEventQueue();

    expect(projection.callCount, 2);
    expect(projection.maxConcurrent, 1);

    projection.release.complete();
    await pumpEventQueue();
    expect(projection.callCount, 3);
    expect(projection.maxConcurrent, 1);

    await session.dispose();
    await projectionDb.close();
  });
}

class RecordingTaskProjectionEngine extends TaskProjectionEngine {
  RecordingTaskProjectionEngine({required super.database});

  final List<String> userIds = [];

  @override
  Future<void> projectTasksFromDocument({
    required String noteId,
    required MutableDocument document,
    String userId = '',
  }) async {
    userIds.add(userId);
  }
}

class GateTaskProjectionEngine extends TaskProjectionEngine {
  GateTaskProjectionEngine({required super.database});

  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<void> projectTasksFromDocument({
    required String noteId,
    required MutableDocument document,
    String userId = '',
  }) async {
    if (!started.isCompleted) started.complete();
    await release.future;
  }
}

class BlockingTaskProjectionEngine extends TaskProjectionEngine {
  BlockingTaskProjectionEngine({required super.database});

  final Completer<void> release = Completer<void>();
  int callCount = 0;
  int concurrent = 0;
  int maxConcurrent = 0;

  @override
  Future<void> projectTasksFromDocument({
    required String noteId,
    required MutableDocument document,
    String userId = '',
  }) async {
    callCount++;
    concurrent++;
    if (concurrent > maxConcurrent) maxConcurrent = concurrent;
    if (callCount > 1) await release.future;
    concurrent--;
  }
}

class FailingTaskProjectionEngine extends TaskProjectionEngine {
  FailingTaskProjectionEngine({
    required super.database,
    required this.failuresRemaining,
  });

  int failuresRemaining;

  @override
  Future<void> projectTasksFromDocument({
    required String noteId,
    required MutableDocument document,
    String userId = '',
  }) async {
    if (failuresRemaining > 0) {
      failuresRemaining--;
      throw StateError('projection failed');
    }
  }
}
