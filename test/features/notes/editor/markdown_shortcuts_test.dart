import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';
import 'package:supanotes/features/notes/editor/application/note_editor_controller.dart';

void main() {
  test('Super Editor Markdown plugin converts inline syntax', () async {
    final controller = NoteEditorController(userId: 'user-1', noteId: 'note-1');
    final plugin = MarkdownInlineUpstreamSyntaxPlugin();
    plugin.attach(controller.editor);
    addTearDown(() {
      plugin.detach(controller.editor);
      controller.dispose();
    });

    controller.editor.execute([
      InsertTextRequest(
        documentPosition: const DocumentPosition(
          nodeId: 'init',
          nodePosition: TextNodePosition(offset: 0),
        ),
        textToInsert: '**bold**',
        attributions: const {},
      ),
    ]);

    final text = (controller.document.first! as ParagraphNode).text;
    expect(text.toPlainText(), 'bold');
    expect(text.hasAttributionAt(0, attribution: boldAttribution), isTrue);
  });

  test(
    'default Super Editor reactions convert Markdown block prefixes',
    () async {
      final controller = NoteEditorController(
        userId: 'user-1',
        noteId: 'note-1',
      );
      addTearDown(controller.dispose);

      controller.editor.execute([
        InsertTextRequest(
          documentPosition: DocumentPosition(
            nodeId: 'init',
            nodePosition: TextNodePosition(offset: 0),
          ),
          textToInsert: '# ',
          attributions: {},
        ),
      ]);

      expect(controller.document.first, isA<ParagraphNode>());
      expect(
        (controller.document.first! as ParagraphNode).getMetadataValue(
          'blockType',
        ),
        header1Attribution,
      );
    },
  );

  for (final prefix in ['[] ', '- [ ] ']) {
    test('converts $prefix to an incomplete task', () async {
      final controller = NoteEditorController(
        userId: 'user-1',
        noteId: 'note-1',
      );
      addTearDown(controller.dispose);

      controller.editor.execute([
        InsertTextRequest(
          documentPosition: const DocumentPosition(
            nodeId: 'init',
            nodePosition: TextNodePosition(offset: 0),
          ),
          textToInsert: prefix,
          attributions: const {},
        ),
      ]);

      expect(controller.document.first, isA<TaskNode>());
      expect((controller.document.first! as TaskNode).text.toPlainText(), '');
      expect((controller.document.first! as TaskNode).isComplete, isFalse);
    });
  }
}
