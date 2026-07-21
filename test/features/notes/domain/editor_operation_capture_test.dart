import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';

import 'package:supanotes/features/notes/domain/editor_operation_capture.dart';
import 'package:supanotes/features/notes/domain/ot_document_codec.dart';

void main() {
  group('EditorOperationCapture Formatting & Attributed Text Tests', () {
    const codec = OtDocumentCodec();

    test('captures bold formatting change on identical text', () {
      final doc = MutableDocument(
        nodes: [
          ParagraphNode(
            id: 'n1',
            text: AttributedText('Hello World'),
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
      final textDeltaOp = capturedOps.firstWhere((op) => op.kind == 'text_delta');
      expect(textDeltaOp.blockId, 'n1');

      final opsList = textDeltaOp.payload['ops'] as List<dynamic>;
      expect(opsList.first['retain'], 5);
      expect(opsList.first['attributes'], {'bold': true});
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
      final occurrenceOp = capturedOps.firstWhere((op) => op.kind == 'complete_task_occurrence');
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
            metadata: {
              'recurrenceRule': 'FREQ=DAILY',
              'completions': {},
            },
          ),
        ),
      ]);

      expect(capturedOps.isNotEmpty, true);
      final reopenOp = capturedOps.firstWhere((op) => op.kind == 'complete_task_occurrence');
      expect(reopenOp.payload['taskId'], 't1');
      expect(reopenOp.payload['scheduledAt'], schedAt);
      expect(reopenOp.payload['completedAt'], null);
    });
  });
}
