import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:super_editor/super_editor.dart';

import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/sync/note_operations_sync_service.dart';
import 'package:supanotes/features/notes/data/note_operations_api.dart';
import 'package:supanotes/features/notes/domain/note_operation_adapter.dart';

class MockSyncService extends Mock implements NoteOperationsSyncService {}

class FakeOperationRequest extends Fake implements OperationRequest {}

void main() {
  late MockSyncService mockSyncService;
  late MutableDocument document;
  late MutableDocumentComposer composer;
  late Editor editor;

  setUpAll(() {
    registerFallbackValue(FakeOperationRequest());
    registerFallbackValue('note-1');
  });

  setUp(() {
    mockSyncService = MockSyncService();
    document = MutableDocument(
      nodes: [ParagraphNode(id: 'block-1', text: AttributedText('Hello'))],
    );
    composer = MutableDocumentComposer();
    editor = createDefaultDocumentEditor(
      document: document,
      composer: composer,
    );

    when(() => mockSyncService.generateOperationId()).thenReturn('test-op-id');
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
  });

  NoteOperationAdapter createAdapter() {
    return NoteOperationAdapter(
      document: document,
      syncService: mockSyncService,
      noteId: 'note-1',
      editor: editor,
    );
  }

  group('text changes', () {
    test('produces text_delta when text is inserted', () async {
      final adapter = createAdapter();

      List<OperationRequest>? capturedOps;
      adapter.onLocalOperations = (ops) {
        capturedOps = ops;
      };

      adapter.start();
      await Future.delayed(Duration.zero);

      final pos = DocumentPosition(
        nodeId: 'block-1',
        nodePosition: const TextNodePosition(offset: 5),
      );
      editor.execute([
        InsertTextRequest(
          documentPosition: pos,
          textToInsert: ' World',
          attributions: {},
        ),
      ]);

      await adapter.flushNow();

      expect(capturedOps, isNotNull);
      expect(capturedOps!.length, 1);
      expect(capturedOps!.first.kind, 'text_delta');
      expect(capturedOps!.first.blockId, 'block-1');

      final ops = capturedOps!.first.payload['ops'] as List<dynamic>;
      expect(ops, isNotEmpty);
      expect(ops.any((o) => (o as Map).containsKey('insert')), true);
    });

    test(
      'produces text_delta via ReplaceNodeRequest on same block ID',
      () async {
        final adapter = createAdapter();

        List<OperationRequest>? capturedOps;
        adapter.onLocalOperations = (ops) {
          capturedOps = ops;
        };

        adapter.start();
        await Future.delayed(Duration.zero);

        editor.execute([
          ReplaceNodeRequest(
            existingNodeId: 'block-1',
            newNode: ParagraphNode(
              id: 'block-1',
              text: AttributedText('Hello World'),
            ),
          ),
        ]);

        await adapter.flushNow();

        expect(capturedOps, isNotNull);
        expect(capturedOps!.length, 1);
        expect(capturedOps!.first.kind, 'text_delta');
        expect(capturedOps!.first.blockId, 'block-1');
      },
    );
  });

  group('block operations', () {
    test('produces create_block when a node is inserted', () async {
      final adapter = createAdapter();

      List<OperationRequest>? capturedOps;
      adapter.onLocalOperations = (ops) {
        capturedOps = ops;
      };

      adapter.start();
      await Future.delayed(Duration.zero);
      capturedOps = null;

      editor.execute([
        InsertNodeAtIndexRequest(
          nodeIndex: 1,
          newNode: ParagraphNode(
            id: 'block-2',
            text: AttributedText('Second block'),
          ),
        ),
      ]);

      await adapter.flushNow();

      expect(capturedOps, isNotNull);
      expect(capturedOps!.any((op) => op.kind == 'create_block'), true);
      expect(
        capturedOps!.firstWhere((op) => op.kind == 'create_block').blockId,
        'block-2',
      );
    });

    test('captures text changes after a created task as text_delta', () async {
      final adapter = createAdapter();
      final capturedBatches = <List<OperationRequest>>[];
      adapter.onLocalOperations = (ops) {
        capturedBatches.add(List<OperationRequest>.from(ops));
      };

      await adapter.start();
      editor.execute([
        InsertNodeAtIndexRequest(
          nodeIndex: 1,
          newNode: TaskNode(
            id: 'task-1',
            text: AttributedText(),
            isComplete: false,
          ),
        ),
      ]);
      await adapter.flushNow();

      editor.execute([
        ReplaceNodeRequest(
          existingNodeId: 'task-1',
          newNode: TaskNode(
            id: 'task-1',
            text: AttributedText('First word'),
            isComplete: false,
          ),
        ),
      ]);
      await adapter.flushNow();

      final operations = capturedBatches.expand((batch) => batch).toList();
      expect(
        operations.where((operation) => operation.kind == 'create_block'),
        hasLength(1),
      );
      expect(
        operations.where((operation) => operation.kind == 'text_delta'),
        hasLength(1),
      );
    });

    test('produces delete_block when a node is removed', () async {
      final adapter = createAdapter();

      List<OperationRequest>? capturedOps;
      adapter.onLocalOperations = (ops) {
        capturedOps = ops;
      };

      adapter.start();
      await Future.delayed(Duration.zero);
      capturedOps = null;

      editor.execute([DeleteNodeRequest(nodeId: 'block-1')]);

      await adapter.flushNow();

      expect(capturedOps, isNotNull);
      expect(capturedOps!.any((op) => op.kind == 'delete_block'), true);
      expect(
        capturedOps!.firstWhere((op) => op.kind == 'delete_block').blockId,
        'block-1',
      );
    });

    test('produces move_block when a node is moved', () async {
      editor.execute([
        InsertNodeAtIndexRequest(
          nodeIndex: 1,
          newNode: ParagraphNode(id: 'block-2', text: AttributedText('Second')),
        ),
      ]);

      final adapter = createAdapter();

      List<OperationRequest>? capturedOps;
      adapter.onLocalOperations = (ops) {
        capturedOps = ops;
      };

      adapter.start();
      await Future.delayed(Duration.zero);
      capturedOps = null;

      editor.execute([MoveNodeRequest(nodeId: 'block-2', newIndex: 0)]);

      await adapter.flushNow();

      expect(capturedOps, isNotNull);
      expect(capturedOps!.any((op) => op.kind == 'move_block'), true);
    });

    test('produces set_block_type when block type changes', () async {
      final adapter = createAdapter();

      List<OperationRequest>? capturedOps;
      adapter.onLocalOperations = (ops) {
        capturedOps = ops;
      };

      adapter.start();
      await Future.delayed(Duration.zero);
      capturedOps = null;

      editor.execute([
        ChangeParagraphBlockTypeRequest(
          nodeId: 'block-1',
          blockType: header1Attribution,
        ),
      ]);

      await adapter.flushNow();

      expect(capturedOps, isNotNull);
      expect(capturedOps!.any((op) => op.kind == 'set_block_type'), true);
    });
  });

  group('remote operations', () {
    test(
      'keeps a valid selection after a remote snapshot shortens text',
      () async {
        final adapter = createAdapter();
        composer.setSelectionWithReason(
          DocumentSelection.collapsed(
            position: DocumentPosition(
              nodeId: 'block-1',
              nodePosition: const TextNodePosition(offset: 5),
            ),
          ),
        );

        await adapter.reconcile(
          SyncResult(
            acceptedCount: 1,
            acceptedOperationIds: ['remote-selection'],
            finalRevision: 1,
            remoteOperations: [
              Operation(
                operationId: 'remote-selection',
                noteId: 'note-1',
                revision: 1,
                baseRevision: 0,
                actorId: '',
                kind: 'text_delta',
                blockId: 'block-1',
                payload: const {'ops': []},
                createdAt: DateTime.utc(2026, 7, 22),
              ),
            ],
            canonicalDocument: NoteDocumentResponse(
              noteId: 'note-1',
              revision: 1,
              document: {
                'blocks': [
                  {
                    'id': 'block-1',
                    'type': 'paragraph',
                    'delta': [
                      {'insert': 'Hi'},
                    ],
                  },
                ],
              },
              serverTime: DateTime.utc(2026, 7, 22),
            ),
          ),
        );

        final selection = composer.selection;
        expect(selection, isNotNull);
        expect(selection!.extent.nodeId, 'block-1');
        expect((selection.extent.nodePosition as TextNodePosition).offset, 2);
      },
    );

    test('does not project duplicate block IDs from a snapshot', () async {
      final adapter = createAdapter();

      await adapter.reconcile(
        SyncResult(
          acceptedCount: 1,
          acceptedOperationIds: ['remote-duplicate'],
          finalRevision: 1,
          remoteOperations: [
            Operation(
              operationId: 'remote-duplicate',
              noteId: 'note-1',
              revision: 1,
              baseRevision: 0,
              actorId: '',
              kind: 'create_block',
              blockId: 'block-1',
              payload: const {},
              createdAt: DateTime.utc(2026, 7, 22),
            ),
          ],
          canonicalDocument: NoteDocumentResponse(
            noteId: 'note-1',
            revision: 1,
            document: {
              'blocks': [
                {
                  'id': 'block-1',
                  'type': 'paragraph',
                  'delta': [
                    {'insert': 'First'},
                  ],
                },
                {
                  'id': 'block-1',
                  'type': 'paragraph',
                  'delta': [
                    {'insert': 'Second'},
                  ],
                },
              ],
            },
            serverTime: DateTime.utc(2026, 7, 22),
          ),
        ),
      );

      expect(document.nodeCount, 1);
      expect((document.first as TextNode).text.toPlainText(), 'First');
    });

    test('does not rebuild after accepting only local operations', () async {
      final adapter = createAdapter();
      await adapter.start();

      await adapter.reconcile(
        SyncResult(
          acceptedCount: 1,
          acceptedOperationIds: ['local-1'],
          finalRevision: 1,
          remoteOperations: [],
          canonicalDocument: NoteDocumentResponse(
            noteId: 'note-1',
            revision: 1,
            document: {
              'blocks': [
                {
                  'id': 'block-1',
                  'type': 'paragraph',
                  'delta': [
                    {'insert': 'Server copy'},
                  ],
                },
              ],
            },
            serverTime: DateTime.utc(2026, 7, 20),
          ),
        ),
      );

      final node = document.getNodeById('block-1') as TextNode?;
      expect(node, isNotNull);
      expect(node!.text.toPlainText(), 'Hello');
      expect(adapter.confirmedRevision, 1);
    });

    test('does not rebuild while local operations remain pending', () async {
      when(() => mockSyncService.loadPendingProjection('note-1')).thenAnswer(
        (_) async => [
          PendingNoteOperationData(
            operationId: 'pending-1',
            noteId: 'note-1',
            baseRevision: 1,
            ordinal: 0,
            kind: 'text_delta',
            blockId: 'block-1',
            payloadJson: '{"ops":[{"retain":5},{"insert":" pending"}]}',
            createdAt: DateTime.utc(2026, 7, 22),
            status: 'pending',
            attemptCount: 0,
          ),
        ],
      );
      final adapter = createAdapter();
      await adapter.start();

      await adapter.reconcile(
        SyncResult(
          acceptedCount: 1,
          acceptedOperationIds: ['local-1'],
          finalRevision: 1,
          remoteOperations: [],
          canonicalDocument: NoteDocumentResponse(
            noteId: 'note-1',
            revision: 1,
            document: {
              'blocks': [
                {
                  'id': 'block-1',
                  'type': 'paragraph',
                  'delta': [
                    {'insert': 'Server copy'},
                  ],
                },
              ],
            },
            serverTime: DateTime.utc(2026, 7, 22),
          ),
        ),
      );

      final node = document.getNodeById('block-1') as TextNode?;
      expect(node?.text.toPlainText(), 'Hello');
      expect(adapter.confirmedRevision, 1);
    });

    test('applies text_delta to document', () async {
      final adapter = createAdapter();
      adapter.start();

      await adapter.reconcile(
        SyncResult(
          acceptedCount: 1,
          acceptedOperationIds: ['remote-1'],
          finalRevision: 1,
          remoteOperations: [
            Operation(
              operationId: 'remote-1',
              noteId: 'note-1',
              revision: 1,
              baseRevision: 0,
              actorId: '',
              kind: 'text_delta',
              blockId: 'block-1',
              payload: {
                'ops': [
                  {'retain': 5},
                  {'insert': ' World'},
                ],
              },
              createdAt: DateTime.utc(2026, 7, 20),
            ),
          ],
          canonicalDocument: NoteDocumentResponse(
            noteId: 'note-1',
            revision: 1,
            document: {
              'blocks': [
                {
                  'id': 'block-1',
                  'type': 'paragraph',
                  'delta': [
                    {'insert': 'Hello World'},
                  ],
                },
              ],
            },
            serverTime: DateTime.utc(2026, 7, 20),
          ),
        ),
      );

      final node = document.getNodeById('block-1') as TextNode?;
      expect(node, isNotNull);
      expect(node!.text.toPlainText(), 'Hello World');
    });

    test('applies create_block to document', () async {
      final adapter = createAdapter();
      adapter.start();

      await adapter.reconcile(
        SyncResult(
          acceptedCount: 1,
          acceptedOperationIds: ['remote-2'],
          finalRevision: 1,
          remoteOperations: [
            Operation(
              operationId: 'remote-2',
              noteId: 'note-1',
              revision: 1,
              baseRevision: 0,
              actorId: '',
              kind: 'create_block',
              blockId: 'block-2',
              payload: {
                'id': 'block-2',
                'type': 'paragraph',
                'delta': [
                  {'insert': 'Remote block'},
                ],
                'afterBlockId': null,
              },
              createdAt: DateTime.utc(2026, 7, 20),
            ),
          ],
          canonicalDocument: NoteDocumentResponse(
            noteId: 'note-1',
            revision: 1,
            document: {
              'blocks': [
                {
                  'id': 'block-1',
                  'type': 'paragraph',
                  'delta': [
                    {'insert': 'Hello'},
                  ],
                },
                {
                  'id': 'block-2',
                  'type': 'paragraph',
                  'delta': [
                    {'insert': 'Remote block'},
                  ],
                },
              ],
            },
            serverTime: DateTime.utc(2026, 7, 20),
          ),
        ),
      );

      expect(document.getNodeById('block-2'), isNotNull);
    });

    test('applies delete_block to document', () async {
      final adapter = createAdapter();
      adapter.start();

      await adapter.reconcile(
        SyncResult(
          acceptedCount: 1,
          acceptedOperationIds: ['remote-3'],
          finalRevision: 1,
          remoteOperations: [
            Operation(
              operationId: 'remote-3',
              noteId: 'note-1',
              revision: 1,
              baseRevision: 0,
              actorId: '',
              kind: 'delete_block',
              blockId: 'block-1',
              payload: {'blockId': 'block-1'},
              createdAt: DateTime.utc(2026, 7, 20),
            ),
          ],
          canonicalDocument: NoteDocumentResponse(
            noteId: 'note-1',
            revision: 1,
            document: {'blocks': <dynamic>[]},
            serverTime: DateTime.utc(2026, 7, 20),
          ),
        ),
      );

      expect(document.getNodeById('block-1'), isNull);
    });

    test('applies set_block_type to document', () async {
      final adapter = createAdapter();
      adapter.start();

      await adapter.reconcile(
        SyncResult(
          acceptedCount: 1,
          acceptedOperationIds: ['remote-4'],
          finalRevision: 1,
          remoteOperations: [
            Operation(
              operationId: 'remote-4',
              noteId: 'note-1',
              revision: 1,
              baseRevision: 0,
              actorId: '',
              kind: 'set_block_type',
              blockId: 'block-1',
              payload: {'type': 'header1'},
              createdAt: DateTime.utc(2026, 7, 20),
            ),
          ],
          canonicalDocument: NoteDocumentResponse(
            noteId: 'note-1',
            revision: 1,
            document: {
              'blocks': [
                {
                  'id': 'block-1',
                  'type': 'header1',
                  'delta': [
                    {'insert': 'Hello'},
                  ],
                },
              ],
            },
            serverTime: DateTime.utc(2026, 7, 20),
          ),
        ),
      );

      final node = document.getNodeById('block-1') as ParagraphNode?;
      expect(node, isNotNull);
      expect(node!.getMetadataValue('blockType'), header1Attribution);
    });

    test('resumes listening after reconciling', () async {
      final adapter = createAdapter();

      List<OperationRequest>? capturedOps;
      adapter.onLocalOperations = (ops) {
        capturedOps = ops;
      };

      adapter.start();
      await Future.delayed(Duration.zero);
      capturedOps = null;

      await adapter.reconcile(
        SyncResult(
          acceptedCount: 1,
          acceptedOperationIds: ['remote-5'],
          finalRevision: 1,
          remoteOperations: [
            Operation(
              operationId: 'remote-5',
              noteId: 'note-1',
              revision: 1,
              baseRevision: 0,
              actorId: '',
              kind: 'text_delta',
              blockId: 'block-1',
              payload: {
                'ops': [
                  {'retain': 5},
                  {'insert': ' World'},
                ],
              },
              createdAt: DateTime.utc(2026, 7, 20),
            ),
          ],
          canonicalDocument: NoteDocumentResponse(
            noteId: 'note-1',
            revision: 1,
            document: {
              'blocks': [
                {
                  'id': 'block-1',
                  'type': 'paragraph',
                  'delta': [
                    {'insert': 'Hello World'},
                  ],
                },
              ],
            },
            serverTime: DateTime.utc(2026, 7, 20),
          ),
        ),
      );

      editor.execute([
        ReplaceNodeRequest(
          existingNodeId: 'block-1',
          newNode: ParagraphNode(
            id: 'block-1',
            text: AttributedText('Hello World!'),
          ),
        ),
      ]);
      await adapter.flushNow();

      expect(capturedOps, isNotNull);
    });
  });

  group('flushNow', () {
    test('flushes pending operations immediately', () async {
      final adapter = createAdapter();

      List<OperationRequest>? capturedOps;
      adapter.onLocalOperations = (ops) {
        capturedOps = ops;
      };

      adapter.start();
      await Future.delayed(Duration.zero);
      capturedOps = null;

      editor.execute([
        InsertNodeAtIndexRequest(
          nodeIndex: 1,
          newNode: ParagraphNode(
            id: 'block-2',
            text: AttributedText('New block'),
          ),
        ),
      ]);

      await adapter.flushNow();

      expect(capturedOps, isNotNull);
      expect(capturedOps!.any((op) => op.kind == 'create_block'), true);
    });
  });

  group('confirmedRevision', () {
    test(
      'replaces the local seed with the confirmed document on start',
      () async {
        when(() => mockSyncService.getConfirmedDocument('note-1')).thenAnswer(
          (_) async => LocalNoteDocumentData(
            noteId: 'note-1',
            revision: 1,
            documentJson:
                '{"blocks":[{"id":"remote-1","type":"paragraph","delta":[{"insert":"Remote"}],"metadata":{}}]}',
            updatedAt: DateTime.utc(2026, 7, 20),
          ),
        );

        final adapter = createAdapter();
        await adapter.start();

        expect(document.nodeCount, 1);
        final node = document.getNodeById('remote-1') as TextNode?;
        expect(node?.text.toPlainText(), 'Remote');
      },
    );

    test('loads confirmed revision from sync service', () async {
      when(() => mockSyncService.getConfirmedDocument('note-1')).thenAnswer(
        (_) async => LocalNoteDocumentData(
          noteId: 'note-1',
          revision: 42,
          documentJson: '{}',
          updatedAt: DateTime.utc(2026, 7, 20),
        ),
      );

      final adapter = createAdapter();
      adapter.start();
      await Future.delayed(Duration.zero);

      expect(adapter.confirmedRevision, 42);
    });
  });

  group('flushNow', () {
    test(
      'awaits in-flight _flushLocalOps even when _pendingOps has already been emptied',
      () async {
        final adapter = createAdapter();
        adapter.start();
        await Future.delayed(Duration.zero);

        final completer = Completer<void>();
        when(
          () => mockSyncService.enqueueOperation(any(), any()),
        ).thenAnswer((_) => completer.future);

        editor.execute([
          InsertTextRequest(
            documentPosition: DocumentPosition(
              nodeId: 'block-1',
              nodePosition: const TextNodePosition(offset: 5),
            ),
            textToInsert: ' World',
            attributions: {},
          ),
        ]);

        final firstFlushFuture = adapter.flushNow();

        bool secondFlushResolved = false;
        final secondFlushFuture = adapter.flushNow().then((_) {
          secondFlushResolved = true;
        });

        await Future.delayed(Duration.zero);
        expect(secondFlushResolved, false);

        completer.complete();
        await firstFlushFuture;
        await secondFlushFuture;

        expect(secondFlushResolved, true);
      },
    );
  });

  group('dispose', () {
    test('stops listening to document changes', () async {
      final adapter = createAdapter();
      adapter.start();
      await Future.delayed(Duration.zero);

      adapter.dispose();

      List<OperationRequest>? capturedOps;
      adapter.onLocalOperations = (ops) {
        capturedOps = ops;
      };

      editor.execute([
        ReplaceNodeRequest(
          existingNodeId: 'block-1',
          newNode: ParagraphNode(
            id: 'block-1',
            text: AttributedText('Hello World'),
          ),
        ),
      ]);
      await adapter.flushNow();

      expect(capturedOps, isNull);
    });
  });
}
