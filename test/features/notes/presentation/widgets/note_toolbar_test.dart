import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';
import 'package:supanotes/features/notes/presentation/widgets/custom_task_component.dart';
import 'package:supanotes/features/notes/presentation/widgets/note_toolbar.dart';

Widget buildEditorHarness({
  required List<DocumentNode> nodes,
  DocumentSelection? selection,
}) {
  final document = MutableDocument(nodes: nodes);
  final composer = MutableDocumentComposer(
    initialSelection: selection,
  );
  final editor = createDefaultDocumentEditor(
    document: document,
    composer: composer,
  );

  return MaterialApp(
    home: Scaffold(
      body: NoteToolbar(editor: editor, composer: composer),
    ),
  );
}

DocumentSelection caretSelection(String nodeId) {
  return const DocumentSelection.collapsed(
    position: DocumentPosition(
      nodeId: 'node-1',
      nodePosition: TextNodePosition(offset: 0),
    ),
  );
}

/// Finds the [IconButton] that contains the given [IconData].
Finder iconButtonWithIcon(IconData icon) {
  return find.ancestor(
    of: find.byIcon(icon),
    matching: find.byType(IconButton),
  );
}

Widget buildConversionHarness({
  required List<DocumentNode> nodes,
  DocumentSelection? selection,
}) {
  final document = MutableDocument(nodes: nodes);
  final composer = MutableDocumentComposer(
    initialSelection: selection,
  );
  final editor = createDefaultDocumentEditor(
    document: document,
    composer: composer,
  );

  return MaterialApp(
    home: Scaffold(
      body: Column(
        children: [
          Expanded(
            child: SuperEditor(
              editor: editor,
              componentBuilders: [
                ...defaultComponentBuilders,
                CustomTaskComponentBuilder(editor),
              ],
            ),
          ),
          NoteToolbar(editor: editor, composer: composer),
        ],
      ),
    ),
  );
}

void main() {
  group('Task button isActive', () {
    testWidgets('is inactive when cursor is on a ParagraphNode', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildEditorHarness(
          nodes: [
            ParagraphNode(
              id: 'node-1',
              text: AttributedText('Hello'),
            ),
          ],
          selection: const DocumentSelection.collapsed(
            position: DocumentPosition(
              nodeId: 'node-1',
              nodePosition: TextNodePosition(offset: 0),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final checkbox = iconButtonWithIcon(Icons.check_box_outlined);
      expect(checkbox, findsOneWidget);

      final iconButton = tester.widget<IconButton>(checkbox);
      expect(iconButton.isSelected, isFalse);
    });

    testWidgets('is active when cursor is on a TaskNode', (tester) async {
      await tester.pumpWidget(
        buildEditorHarness(
          nodes: [
            TaskNode(
              id: 'node-1',
              text: AttributedText('Buy milk'),
              isComplete: false,
            ),
          ],
          selection: const DocumentSelection.collapsed(
            position: DocumentPosition(
              nodeId: 'node-1',
              nodePosition: TextNodePosition(offset: 0),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final checkbox = iconButtonWithIcon(Icons.check_box_outlined);
      expect(checkbox, findsOneWidget);

      final iconButton = tester.widget<IconButton>(checkbox);
      expect(iconButton.isSelected, isTrue);
    });
  });

  group('_convertToTask', () {
    testWidgets('converts ParagraphNode to TaskNode', (tester) async {
      final document = MutableDocument(nodes: [
        ParagraphNode(id: 'node-1', text: AttributedText('Buy milk')),
      ]);
      final composer = MutableDocumentComposer(
        initialSelection: const DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: 'node-1',
            nodePosition: TextNodePosition(offset: 0),
          ),
        ),
      );
      final editor = createDefaultDocumentEditor(
        document: document,
        composer: composer,
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(children: [
            Expanded(
              child: SuperEditor(
                editor: editor,
                componentBuilders: [
                  ...defaultComponentBuilders,
                  CustomTaskComponentBuilder(editor),
                ],
              ),
            ),
            NoteToolbar(editor: editor, composer: composer),
          ]),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.check_box_outlined));
      await tester.pumpAndSettle();

      expect(document.first, isA<TaskNode>());
      expect(
        (document.first as TaskNode).text.toPlainText(),
        'Buy milk',
      );
    });

    testWidgets('converts ListItemNode to TaskNode', (tester) async {
      final document = MutableDocument(nodes: [
        ListItemNode.unordered(id: 'node-1', text: AttributedText('Buy milk')),
      ]);
      final composer = MutableDocumentComposer(
        initialSelection: const DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: 'node-1',
            nodePosition: TextNodePosition(offset: 0),
          ),
        ),
      );
      final editor = createDefaultDocumentEditor(
        document: document,
        composer: composer,
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(children: [
            Expanded(
              child: SuperEditor(
                editor: editor,
                componentBuilders: [
                  ...defaultComponentBuilders,
                  CustomTaskComponentBuilder(editor),
                ],
              ),
            ),
            NoteToolbar(editor: editor, composer: composer),
          ]),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.check_box_outlined));
      await tester.pumpAndSettle();

      expect(document.first, isA<TaskNode>());
      expect(
        (document.first as TaskNode).text.toPlainText(),
        'Buy milk',
      );
    });

    testWidgets('converts TaskNode back to ParagraphNode', (tester) async {
      final document = MutableDocument(nodes: [
        TaskNode(
          id: 'node-1',
          text: AttributedText('Buy milk'),
          isComplete: false,
        ),
      ]);
      final composer = MutableDocumentComposer(
        initialSelection: const DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: 'node-1',
            nodePosition: TextNodePosition(offset: 0),
          ),
        ),
      );
      final editor = createDefaultDocumentEditor(
        document: document,
        composer: composer,
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(children: [
            Expanded(
              child: SuperEditor(
                editor: editor,
                componentBuilders: [
                  ...defaultComponentBuilders,
                  CustomTaskComponentBuilder(editor),
                ],
              ),
            ),
            NoteToolbar(editor: editor, composer: composer),
          ]),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.check_box_outlined));
      await tester.pumpAndSettle();

      expect(document.first, isA<ParagraphNode>());
      expect(
        (document.first as ParagraphNode).text.toPlainText(),
        'Buy milk',
      );
    });
  });
}
