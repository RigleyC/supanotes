import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';
import 'package:supanotes/features/notes/domain/note_document_codec.dart';

void main() {
  testWidgets('renders a paragraph hydrated from JSON blockType metadata', (
    tester,
  ) async {
    const codec = NoteDocumentCodec();
    final document = MutableDocument(
      nodes: [
        codec.decodeNode({
          'id': 'heading-1',
          'type': 'paragraph',
          'delta': [
            {'insert': 'Heading'},
          ],
          'metadata': {'blockType': 'header1'},
        }),
      ],
    );
    final composer = MutableDocumentComposer();
    final editor = createDefaultDocumentEditor(
      document: document,
      composer: composer,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SuperEditor(
            editor: editor,
            componentBuilders: defaultComponentBuilders,
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
