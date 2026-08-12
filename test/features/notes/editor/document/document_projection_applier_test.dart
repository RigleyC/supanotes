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
}
