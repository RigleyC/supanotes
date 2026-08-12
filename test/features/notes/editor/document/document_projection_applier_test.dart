import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';

import 'package:supanotes/features/notes/editor/document/document_projection_applier.dart';
import 'package:supanotes/features/notes/editor/document/note_document_codec.dart';
import 'package:supanotes/features/notes/editor/sync/note_operation_contract.dart';

void main() {
  test('moves a block after a later block', () {
    final document = MutableDocument(
      nodes: [
        ParagraphNode(id: 'block-a', text: AttributedText('A')),
        ParagraphNode(id: 'block-b', text: AttributedText('B')),
        ParagraphNode(id: 'block-c', text: AttributedText('C')),
        ParagraphNode(id: 'block-d', text: AttributedText('D')),
      ],
    );
    final editor = createDefaultDocumentEditor(
      document: document,
      composer: MutableDocumentComposer(),
    );
    final applier = DocumentProjectionApplier(
      document: document,
      editor: editor,
      codec: const NoteDocumentCodec(),
    );
    applier.applyOperationPayload(
      kind: NoteOperationWireNames.moveBlock,
      blockId: 'block-a',
      payload: const {'blockId': 'block-a', 'afterBlockId': 'block-c'},
    );

    expect(document.toList().map((node) => node.id), [
      'block-b',
      'block-c',
      'block-a',
      'block-d',
    ]);
  });

  test('preserves task indentation when applying a text delta', () {
    final document = MutableDocument(
      nodes: [
        TaskNode(
          id: 'task-1',
          text: AttributedText('Task'),
          isComplete: false,
          indent: 2,
        ),
      ],
    );
    final editor = createDefaultDocumentEditor(
      document: document,
      composer: MutableDocumentComposer(),
    );
    final applier = DocumentProjectionApplier(
      document: document,
      editor: editor,
      codec: const NoteDocumentCodec(),
    );

    applier.applyOperationPayload(
      kind: NoteOperationWireNames.textDelta,
      blockId: 'task-1',
      payload: const {
        'ops': [
          {'retain': 4},
          {'insert': '!'},
        ],
      },
    );

    final task = document.getNodeById('task-1')! as TaskNode;
    expect(task.text.toPlainText(), 'Task!');
    expect(task.indent, 2);
  });

  test('applies and clears list indentation metadata', () {
    final document = MutableDocument(
      nodes: [
        ListItemNode.unordered(
          id: 'list-1',
          text: AttributedText('Nested list'),
        ),
      ],
    );
    final editor = createDefaultDocumentEditor(
      document: document,
      composer: MutableDocumentComposer(),
    );
    final applier = DocumentProjectionApplier(
      document: document,
      editor: editor,
      codec: const NoteDocumentCodec(),
    );

    applier.applyOperationPayload(
      kind: NoteOperationWireNames.setBlockMetadata,
      blockId: 'list-1',
      payload: const {
        'metadata': {'indent': 2},
      },
    );
    expect((document.getNodeById('list-1')! as ListItemNode).indent, 2);

    applier.applyOperationPayload(
      kind: NoteOperationWireNames.setBlockMetadata,
      blockId: 'list-1',
      payload: const {
        'metadata': {'indent': null},
      },
    );
    expect((document.getNodeById('list-1')! as ListItemNode).indent, 0);
  });

  test('preserves task indentation when applying metadata', () {
    final document = MutableDocument(
      nodes: [
        TaskNode(
          id: 'task-1',
          text: AttributedText('Nested task'),
          isComplete: false,
          indent: 2,
        ),
      ],
    );
    final editor = createDefaultDocumentEditor(
      document: document,
      composer: MutableDocumentComposer(),
    );
    final applier = DocumentProjectionApplier(
      document: document,
      editor: editor,
      codec: const NoteDocumentCodec(),
    );

    applier.applyOperationPayload(
      kind: NoteOperationWireNames.setBlockMetadata,
      blockId: 'task-1',
      payload: const {
        'metadata': {
          'completions': {'2026-08-12': '2026-08-12T10:00:00Z'},
        },
      },
    );

    final task = document.getNodeById('task-1')! as TaskNode;
    expect(task.metadata['completions'], isA<Map>());
    expect(task.indent, 2);
  });
}
