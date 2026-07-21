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
      nodes: [
        ParagraphNode(id: 'block-1', text: AttributedText('Hello')),
      ],
    );
    composer = MutableDocumentComposer();
    editor = createDefaultDocumentEditor(
      document: document,
      composer: composer,
    );

    when(() => mockSyncService.generateOperationId()).thenReturn('test-op-id');
    when(() => mockSyncService.getConfirmedDocument(any()))
        .thenAnswer((_) async => null);
    when(() => mockSyncService.enqueueOperation(any(), any()))
        .thenAnswer((_) async {});
    when(() => mockSyncService.getPendingOperations(any()))
        .thenAnswer((_) async => []);
    when(() => mockSyncService.getProjectedOutboxOperationCount(any()))
        .thenAnswer((_) async => 0);
    when(() => mockSyncService.fetchDocument(any()))
        .thenAnswer((_) async => null);
    when(() => mockSyncService.loadPendingProjection(any()))
        .thenAnswer((_) async => []);
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

    test('produces create_block+delete_block via ReplaceNodeRequest', () async {
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
      expect(capturedOps!.length, 2);
      expect(capturedOps!.any((op) => op.kind == 'delete_block'), true);
      expect(capturedOps!.any((op) => op.kind == 'create_block'), true);
    });
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
      expect(
        capturedOps!.any((op) => op.kind == 'create_block'),
        true,
      );
      expect(
        capturedOps!.firstWhere((op) => op.kind == 'create_block').blockId,
        'block-2',
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
      expect(
        capturedOps!.any((op) => op.kind == 'delete_block'),
        true,
      );
      expect(
        capturedOps!.firstWhere((op) => op.kind == 'delete_block').blockId,
        'block-1',
      );
    });

    test('produces move_block when a node is moved', () async {
      editor.execute([
        InsertNodeAtIndexRequest(
          nodeIndex: 1,
          newNode: ParagraphNode(
            id: 'block-2',
            text: AttributedText('Second'),
          ),
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
      expect(
        capturedOps!.any((op) => op.kind == 'move_block'),
        true,
      );
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
      expect(
        capturedOps!.any((op) => op.kind == 'set_block_type'),
        true,
      );
    });
  });

  group('remote operations', () {
    test('applies text_delta to document', () async {
      final adapter = createAdapter();
      adapter.start();

      await adapter.reconcile(SyncResult(
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
                'delta': [{'insert': 'Hello World'}],
              },
            ],
          },
          serverTime: DateTime.utc(2026, 7, 20),
        ),
      ));

      final node = document.getNodeById('block-1') as TextNode?;
      expect(node, isNotNull);
      expect(node!.text.toPlainText(), 'Hello World');
    });

    test('applies create_block to document', () async {
      final adapter = createAdapter();
      adapter.start();

      await adapter.reconcile(SyncResult(
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
              'delta': [{'insert': 'Remote block'}],
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
                'delta': [{'insert': 'Hello'}],
              },
              {
                'id': 'block-2',
                'type': 'paragraph',
                'delta': [{'insert': 'Remote block'}],
              },
            ],
          },
          serverTime: DateTime.utc(2026, 7, 20),
        ),
      ));

      expect(document.getNodeById('block-2'), isNotNull);
    });

    test('applies delete_block to document', () async {
      final adapter = createAdapter();
      adapter.start();

      await adapter.reconcile(SyncResult(
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
      ));

      expect(document.getNodeById('block-1'), isNull);
    });

    test('applies set_block_type to document', () async {
      final adapter = createAdapter();
      adapter.start();

      await adapter.reconcile(SyncResult(
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
                'delta': [{'insert': 'Hello'}],
              },
            ],
          },
          serverTime: DateTime.utc(2026, 7, 20),
        ),
      ));

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

      await adapter.reconcile(SyncResult(
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
                'delta': [{'insert': 'Hello World'}],
              },
            ],
          },
          serverTime: DateTime.utc(2026, 7, 20),
        ),
      ));

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
    test('loads confirmed revision from sync service', () async {
      when(() => mockSyncService.getConfirmedDocument('note-1'))
          .thenAnswer(
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
