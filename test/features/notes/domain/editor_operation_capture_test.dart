import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';

import 'package:supanotes/features/notes/editor/sync/editor_operation_capture.dart';
import 'package:supanotes/features/notes/editor/document/note_document_codec.dart';

void main() {
  group('EditorOperationCapture Formatting & Attributed Text Tests', () {
    const codec = NoteDocumentCodec();

    test('captures bold formatting change on identical text', () {
      final doc = MutableDocument(
        nodes: [ParagraphNode(id: 'n1', text: AttributedText('Hello World'))],
      );
      final editor = createDefaultDocumentEditor(
        document: doc,
        composer: MutableDocumentComposer(),
      );

      final capturedOps = <OperationRequestData>[];
      int opIdCounter = 0;

      final capture = EditorOperationCapture(
        document: doc,
        generateOpId: () => 'op-${++opIdCounter}',
        codec: codec,
        onOperationsCaptured: (ops) => capturedOps.addAll(ops),
      );

      capture.start();

      final newSpan = AttributedSpans();
      newSpan.addAttribution(newAttribution: boldAttribution, start: 0, end: 4);

      editor.execute([
        ReplaceNodeRequest(
          existingNodeId: 'n1',
          newNode: ParagraphNode(
            id: 'n1',
            text: AttributedText('Hello World', newSpan),
          ),
        ),
      ]);

      expect(capturedOps.isNotEmpty, true);
      final textDeltaOp = capturedOps.firstWhere(
        (op) => op.kind == 'text_delta',
      );
      expect(textDeltaOp.blockId, 'n1');

      final opsList = textDeltaOp.payload['ops'] as List<dynamic>;
      expect(opsList.first['retain'], 5);
      expect(opsList.first['attributes'], {'bold': true});
    });

    test('does not emit formatting changes with a text insertion', () {
      final oldSpans = AttributedSpans()
        ..addAttribution(newAttribution: boldAttribution, start: 0, end: 4);
      final doc = MutableDocument(
        nodes: [
          ParagraphNode(id: 'n1', text: AttributedText('Hello', oldSpans)),
        ],
      );
      final editor = createDefaultDocumentEditor(
        document: doc,
        composer: MutableDocumentComposer(),
      );
      final capturedOps = <OperationRequestData>[];
      final capture = EditorOperationCapture(
        document: doc,
        generateOpId: () => 'op-1',
        codec: codec,
        onOperationsCaptured: capturedOps.addAll,
      );
      capture.start();

      editor.execute([
        ReplaceNodeRequest(
          existingNodeId: 'n1',
          newNode: ParagraphNode(id: 'n1', text: AttributedText('Hello!')),
        ),
      ]);

      final ops = capturedOps.single.payload['ops'] as List<dynamic>;
      expect(ops, [
        {'retain': 5},
        {'insert': '!'},
      ]);
    });

    test('captures the URI when a link attribution changes in place', () {
      final doc = MutableDocument(
        nodes: [ParagraphNode(id: 'n1', text: AttributedText('Link'))],
      );
      final editor = createDefaultDocumentEditor(
        document: doc,
        composer: MutableDocumentComposer(),
      );
      final capturedOps = <OperationRequestData>[];
      final capture = EditorOperationCapture(
        document: doc,
        generateOpId: () => 'op-1',
        codec: codec,
        onOperationsCaptured: capturedOps.addAll,
      );
      capture.start();

      final uri = Uri.parse('note://target-note');
      final spans = AttributedSpans()
        ..addAttribution(
          newAttribution: LinkAttribution.fromUri(uri),
          start: 0,
          end: 3,
        );
      editor.execute([
        ReplaceNodeRequest(
          existingNodeId: 'n1',
          newNode: ParagraphNode(id: 'n1', text: AttributedText('Link', spans)),
        ),
      ]);

      final textDeltaOp = capturedOps.firstWhere(
        (op) => op.kind == 'text_delta',
      );
      final ops = textDeltaOp.payload['ops'] as List<dynamic>;
      expect(ops, [
        {
          'retain': 4,
          'attributes': {'link:note://target-note': true},
        },
      ]);
    });

    test('does not inherit accidental bold on inserted text', () {
      final boldSpans = AttributedSpans()
        ..addAttribution(newAttribution: boldAttribution, start: 0, end: 6);
      final doc = MutableDocument(
        nodes: [ParagraphNode(id: 'n1', text: AttributedText('Hello'))],
      );
      final editor = createDefaultDocumentEditor(
        document: doc,
        composer: MutableDocumentComposer(),
      );
      final capturedOps = <OperationRequestData>[];
      final capture = EditorOperationCapture(
        document: doc,
        generateOpId: () => 'op-1',
        codec: codec,
        onOperationsCaptured: capturedOps.addAll,
      );
      capture.start();

      editor.execute([
        ReplaceNodeRequest(
          existingNodeId: 'n1',
          newNode: ParagraphNode(
            id: 'n1',
            text: AttributedText('Hello!', boldSpans),
          ),
        ),
      ]);

      final ops = capturedOps.single.payload['ops'] as List<dynamic>;
      expect(ops, [
        {'retain': 5},
        {'insert': '!'},
      ]);
    });

    test('emits complete_task_occurrence on task completion and reopening', () {
      final doc = MutableDocument(
        nodes: [
          TaskNode(
            id: 't1',
            text: AttributedText('Recurring Task'),
            isComplete: false,
            metadata: {'recurrenceRule': 'FREQ=DAILY'},
          ),
        ],
      );
      final editor = createDefaultDocumentEditor(
        document: doc,
        composer: MutableDocumentComposer(),
      );

      final capturedOps = <OperationRequestData>[];
      int opIdCounter = 0;

      final capture = EditorOperationCapture(
        document: doc,
        generateOpId: () => 'op-${++opIdCounter}',
        codec: codec,
        onOperationsCaptured: (ops) => capturedOps.addAll(ops),
      );

      capture.start();

      // 1. Complete occurrence
      const schedAt = '2026-07-21T00:00:00.000Z';
      const compAt = '2026-07-21T17:00:00.000Z';
      editor.execute([
        ReplaceNodeRequest(
          existingNodeId: 't1',
          newNode: TaskNode(
            id: 't1',
            text: AttributedText('Recurring Task'),
            isComplete: false,
            metadata: {
              'recurrenceRule': 'FREQ=DAILY',
              'completions': {schedAt: compAt},
            },
          ),
        ),
      ]);

      expect(capturedOps.isNotEmpty, true);
      expect(capturedOps.any((op) => op.kind == 'set_block_metadata'), false);
      final occurrenceOp = capturedOps.firstWhere(
        (op) => op.kind == 'complete_task_occurrence',
      );
      expect(occurrenceOp.payload['taskId'], 't1');
      expect(occurrenceOp.payload['scheduledAt'], schedAt);
      expect(occurrenceOp.payload['completedAt'], compAt);

      capturedOps.clear();

      // 2. Reopen occurrence (remove scheduledAt from completions)
      editor.execute([
        ReplaceNodeRequest(
          existingNodeId: 't1',
          newNode: TaskNode(
            id: 't1',
            text: AttributedText('Recurring Task'),
            isComplete: false,
            metadata: {'recurrenceRule': 'FREQ=DAILY', 'completions': {}},
          ),
        ),
      ]);

      expect(capturedOps.isNotEmpty, true);
      final reopenOp = capturedOps.firstWhere(
        (op) => op.kind == 'complete_task_occurrence',
      );
      expect(reopenOp.payload['taskId'], 't1');
      expect(reopenOp.payload['scheduledAt'], schedAt);
      expect(reopenOp.payload['completedAt'], null);
    });

    test('captures non-recurring task completion despite stale metadata', () {
      final doc = MutableDocument(
        nodes: [
          TaskNode(
            id: 't1',
            text: AttributedText('Task'),
            isComplete: false,
            metadata: {'isCompleted': false},
          ),
        ],
      );
      final editor = createDefaultDocumentEditor(
        document: doc,
        composer: MutableDocumentComposer(),
      );
      final capturedOps = <OperationRequestData>[];
      final capture = EditorOperationCapture(
        document: doc,
        generateOpId: () => 'op-1',
        codec: codec,
        onOperationsCaptured: capturedOps.addAll,
      );
      capture.start();

      editor.execute([
        ReplaceNodeRequest(
          existingNodeId: 't1',
          newNode: TaskNode(
            id: 't1',
            text: AttributedText('Task'),
            isComplete: true,
            metadata: {'isCompleted': false},
          ),
        ),
      ]);

      final operation = capturedOps.singleWhere(
        (op) => op.kind == 'set_block_metadata',
      );
      final metadata = operation.payload['metadata'] as Map<String, dynamic>;
      expect(metadata['isCompleted'], true);
    });

    test('captures metadata deletions as explicit null values in set_block_metadata payload', () {
      final doc = MutableDocument(
        nodes: [
          TaskNode(
            id: 't1',
            text: AttributedText('Task with metadata'),
            isComplete: false,
            metadata: {
              'dueDate': '2026-07-25T14:30:00.000',
              'hasTime': true,
              'recurrenceRule': 'weekly',
              'reminder': '15m_before',
            },
          ),
        ],
      );
      final editor = createDefaultDocumentEditor(
        document: doc,
        composer: MutableDocumentComposer(),
      );
      final capturedOps = <OperationRequestData>[];
      final capture = EditorOperationCapture(
        document: doc,
        generateOpId: () => 'op-1',
        codec: codec,
        onOperationsCaptured: capturedOps.addAll,
      );
      capture.start();

      // Remove all task metadata keys
      editor.execute([
        ReplaceNodeRequest(
          existingNodeId: 't1',
          newNode: TaskNode(
            id: 't1',
            text: AttributedText('Task with metadata'),
            isComplete: false,
            metadata: {},
          ),
        ),
      ]);

      final operation = capturedOps.singleWhere(
        (op) => op.kind == 'set_block_metadata',
      );
      final metadata = operation.payload['metadata'] as Map<String, dynamic>;
      expect(metadata['dueDate'], null);
      expect(metadata['hasTime'], null);
      expect(metadata['recurrenceRule'], null);
      expect(metadata['reminder'], null);
    });
  });

  group('Task document mutations', () {
    const codec = NoteDocumentCodec();

    test('captures task creation as a create_block operation', () {
      final doc = MutableDocument(nodes: [
        ParagraphNode(id: 'p1', text: AttributedText('Before')),
      ]);
      final editor = createDefaultDocumentEditor(
        document: doc,
        composer: MutableDocumentComposer(),
      );
      final capturedOps = <OperationRequestData>[];
      EditorOperationCapture(
        document: doc,
        generateOpId: () => 'op-create',
        codec: codec,
        onOperationsCaptured: capturedOps.addAll,
      ).start();

      editor.execute([
        InsertNodeAtIndexRequest(
          newNode: TaskNode(
            id: 't1',
            text: AttributedText('New task'),
            isComplete: false,
            metadata: {'dueDate': '2026-08-04T09:00:00.000Z'},
          ),
          nodeIndex: 1,
        ),
      ]);

      final operation = capturedOps.singleWhere(
        (op) => op.kind == 'create_block',
      );
      expect(operation.blockId, 't1');
      expect(operation.payload['type'], 'task');
      expect(operation.payload['afterBlockId'], 'p1');
      expect(
        (operation.payload['metadata'] as Map<String, dynamic>)['dueDate'],
        '2026-08-04T09:00:00.000Z',
      );
    });

    test('captures task deletion as a delete_block operation', () {
      final doc = MutableDocument(nodes: [
        ParagraphNode(id: 'p1', text: AttributedText('Before')),
        TaskNode(
          id: 't1',
          text: AttributedText('Delete me'),
          isComplete: false,
        ),
      ]);
      final editor = createDefaultDocumentEditor(
        document: doc,
        composer: MutableDocumentComposer(),
      );
      final capturedOps = <OperationRequestData>[];
      EditorOperationCapture(
        document: doc,
        generateOpId: () => 'op-delete',
        codec: codec,
        onOperationsCaptured: capturedOps.addAll,
      ).start();

      editor.execute([DeleteNodeRequest(nodeId: 't1')]);

      expect(capturedOps.single.kind, 'delete_block');
      expect(capturedOps.single.blockId, 't1');
    });

    test('captures task reordering as a move_block operation', () {
      final doc = MutableDocument(nodes: [
        ParagraphNode(id: 'p1', text: AttributedText('First')),
        ParagraphNode(id: 'p2', text: AttributedText('Second')),
        TaskNode(
          id: 't1',
          text: AttributedText('Move me'),
          isComplete: false,
        ),
      ]);
      final editor = createDefaultDocumentEditor(
        document: doc,
        composer: MutableDocumentComposer(),
      );
      final capturedOps = <OperationRequestData>[];
      EditorOperationCapture(
        document: doc,
        generateOpId: () => 'op-move',
        codec: codec,
        onOperationsCaptured: capturedOps.addAll,
      ).start();

      editor.execute([
        MoveNodeRequest(nodeId: 't1', newIndex: 0),
      ]);

      final operation = capturedOps.firstWhere(
        (op) => op.kind == 'move_block' && op.blockId == 't1',
      );
      expect(operation.payload['blockId'], 't1');
      expect(operation.payload['afterBlockId'], null);
    });
  });
}
