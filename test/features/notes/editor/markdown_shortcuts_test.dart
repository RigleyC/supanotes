import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';
import 'package:supanotes/features/notes/editor/application/note_editor_controller.dart';
import 'package:supanotes/features/notes/editor/document/markdown_task_shortcut_plugin.dart';

void main() {
  testWidgets('keeps the Markdown plugin lifecycle stable across rebuilds', (
    tester,
  ) async {
    final controller = NoteEditorController(userId: 'user-1', noteId: 'note-1');
    final plugin = MarkdownInlineUpstreamSyntaxPlugin();
    var isDesktop = true;
    late StateSetter updateDesktopMode;
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              updateDesktopMode = setState;
              return SuperEditor(
                key: ValueKey(isDesktop),
                editor: controller.editor,
                plugins: isDesktop ? {plugin} : const {},
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();

    updateDesktopMode(() {});
    await tester.pump();
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

    expect(
      (controller.document.first as ParagraphNode).text.toPlainText(),
      'bold',
    );

    isDesktop = false;
    updateDesktopMode(() {});
    await tester.pump();
  });

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

    final text = (controller.document.first as ParagraphNode).text;
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
        (controller.document.first as ParagraphNode).getMetadataValue(
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
      final plugin = MarkdownTaskShortcutPlugin()..attach(controller.editor);
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
          textToInsert: prefix,
          attributions: const {},
        ),
      ]);

      expect(controller.document.first, isA<TaskNode>());
      expect((controller.document.first as TaskNode).text.toPlainText(), '');
      expect((controller.document.first as TaskNode).isComplete, isFalse);
      expect(
        controller.composer.selection,
        const DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: 'init',
            nodePosition: TextNodePosition(offset: 0),
          ),
        ),
      );

      controller.editor.execute([
        InsertTextRequest(
          documentPosition: const DocumentPosition(
            nodeId: 'init',
            nodePosition: TextNodePosition(offset: 0),
          ),
          textToInsert: 'Task text',
          attributions: const {},
        ),
      ]);
      expect(
        (controller.document.first as TaskNode).text.toPlainText(),
        'Task text',
      );
    });
  }

  test('does not add the task shortcut without the desktop plugin', () async {
    final controller = NoteEditorController(userId: 'user-1', noteId: 'note-1');
    addTearDown(controller.dispose);

    controller.editor.execute([
      InsertTextRequest(
        documentPosition: const DocumentPosition(
          nodeId: 'init',
          nodePosition: TextNodePosition(offset: 0),
        ),
        textToInsert: '[] ',
        attributions: const {},
      ),
    ]);

    expect(controller.document.first, isA<ParagraphNode>());
  });
}
