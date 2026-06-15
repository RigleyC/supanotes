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
  final composer = MutableDocumentComposer(initialSelection: selection);
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
  final composer = MutableDocumentComposer(initialSelection: selection);
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
          nodes: [ParagraphNode(id: 'node-1', text: AttributedText('Hello'))],
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
      final document = MutableDocument(
        nodes: [ParagraphNode(id: 'node-1', text: AttributedText('Buy milk'))],
      );
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

      await tester.pumpWidget(
        MaterialApp(
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
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.check_box_outlined));
      await tester.pumpAndSettle();

      expect(document.first, isA<TaskNode>());
      expect((document.first as TaskNode).text.toPlainText(), 'Buy milk');
    });

    testWidgets('converts ListItemNode to TaskNode', (tester) async {
      final document = MutableDocument(
        nodes: [
          ListItemNode.unordered(
            id: 'node-1',
            text: AttributedText('Buy milk'),
          ),
        ],
      );
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

      await tester.pumpWidget(
        MaterialApp(
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
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.check_box_outlined));
      await tester.pumpAndSettle();

      expect(document.first, isA<TaskNode>());
      expect((document.first as TaskNode).text.toPlainText(), 'Buy milk');
    });

    testWidgets('converts selected ListItemNodes to TaskNodes', (tester) async {
      final document = MutableDocument(
        nodes: [
          ListItemNode.unordered(
            id: 'node-1',
            text: AttributedText('Buy milk'),
          ),
          ListItemNode.unordered(
            id: 'node-2',
            text: AttributedText('Pay rent'),
          ),
          ListItemNode.unordered(
            id: 'node-3',
            text: AttributedText('Call mom'),
          ),
        ],
      );
      final composer = MutableDocumentComposer(
        initialSelection: const DocumentSelection(
          base: DocumentPosition(
            nodeId: 'node-1',
            nodePosition: TextNodePosition(offset: 0),
          ),
          extent: DocumentPosition(
            nodeId: 'node-3',
            nodePosition: TextNodePosition(offset: 8),
          ),
        ),
      );
      final editor = createDefaultDocumentEditor(
        document: document,
        composer: composer,
      );

      await tester.pumpWidget(
        MaterialApp(
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
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.check_box_outlined));
      await tester.pumpAndSettle();

      final nodes = [
        document.getNodeById('node-1'),
        document.getNodeById('node-2'),
        document.getNodeById('node-3'),
      ];

      expect(nodes, everyElement(isA<TaskNode>()));
      expect(nodes.map((node) => (node as TaskNode).text.toPlainText()), [
        'Buy milk',
        'Pay rent',
        'Call mom',
      ]);
    });

    testWidgets('converts TaskNode back to ParagraphNode', (tester) async {
      final document = MutableDocument(
        nodes: [
          TaskNode(
            id: 'node-1',
            text: AttributedText('Buy milk'),
            isComplete: false,
          ),
        ],
      );
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

      await tester.pumpWidget(
        MaterialApp(
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
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.check_box_outlined));
      await tester.pumpAndSettle();

      expect(document.first, isA<ParagraphNode>());
      expect((document.first as ParagraphNode).text.toPlainText(), 'Buy milk');
    });
  });

  group('_convertToListItem', () {
    testWidgets('converts TaskNode to unordered ListItemNode', (tester) async {
      final document = MutableDocument(
        nodes: [
          TaskNode(
            id: 'node-1',
            text: AttributedText('Buy milk'),
            isComplete: false,
          ),
        ],
      );
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

      await tester.pumpWidget(
        MaterialApp(
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
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.format_list_bulleted));
      await tester.pumpAndSettle();

      expect(document.first, isA<ListItemNode>());
      final item = document.first as ListItemNode;
      expect(item.text.toPlainText(), 'Buy milk');
      expect(item.type, ListItemType.unordered);
    });

    testWidgets('converts TaskNode to ordered ListItemNode', (tester) async {
      final document = MutableDocument(
        nodes: [
          TaskNode(
            id: 'node-1',
            text: AttributedText('Buy milk'),
            isComplete: false,
          ),
        ],
      );
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

      await tester.pumpWidget(
        MaterialApp(
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
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.format_list_numbered));
      await tester.pumpAndSettle();

      expect(document.first, isA<ListItemNode>());
      final item = document.first as ListItemNode;
      expect(item.text.toPlainText(), 'Buy milk');
      expect(item.type, ListItemType.ordered);
    });
  });

  group('_setBlockType', () {
    testWidgets('converts ListItemNode to H1', (tester) async {
      final document = MutableDocument(
        nodes: [
          ListItemNode.unordered(
            id: 'node-1',
            text: AttributedText('Heading text'),
          ),
        ],
      );
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

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Expanded(
                  child: SuperEditor(
                    editor: editor,
                    componentBuilders: defaultComponentBuilders,
                  ),
                ),
                NoteToolbar(editor: editor, composer: composer),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('H1'));
      await tester.pumpAndSettle();

      expect(document.first, isA<ParagraphNode>());
      final para = document.first as ParagraphNode;
      expect(para.text.toPlainText(), 'Heading text');
      expect(para.getMetadataValue('blockType'), header1Attribution);
    });

    testWidgets('converts TaskNode to H2', (tester) async {
      final document = MutableDocument(
        nodes: [
          TaskNode(
            id: 'node-1',
            text: AttributedText('Heading text'),
            isComplete: false,
          ),
        ],
      );
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

      await tester.pumpWidget(
        MaterialApp(
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
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('H2'));
      await tester.pumpAndSettle();

      expect(document.first, isA<ParagraphNode>());
      final para = document.first as ParagraphNode;
      expect(para.text.toPlainText(), 'Heading text');
      expect(para.getMetadataValue('blockType'), header2Attribution);
    });

    testWidgets('converts TaskNode to Blockquote', (tester) async {
      final document = MutableDocument(
        nodes: [
          TaskNode(
            id: 'node-1',
            text: AttributedText('Quoted text'),
            isComplete: false,
          ),
        ],
      );
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

      await tester.pumpWidget(
        MaterialApp(
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
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.format_quote));
      await tester.pumpAndSettle();

      expect(document.first, isA<ParagraphNode>());
      final para = document.first as ParagraphNode;
      expect(para.text.toPlainText(), 'Quoted text');
      expect(para.getMetadataValue('blockType'), blockquoteAttribution);
    });
  });

  group('Numbered list button isActive', () {
    testWidgets('is active on ordered list item', (tester) async {
      await tester.pumpWidget(
        buildEditorHarness(
          nodes: [
            ListItemNode.ordered(id: 'node-1', text: AttributedText('Ordered')),
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

      final numberedBtn = iconButtonWithIcon(Icons.format_list_numbered);
      expect(numberedBtn, findsOneWidget);
      final btnWidget = tester.widget<IconButton>(numberedBtn);
      expect(btnWidget.isSelected, isTrue);
    });

    testWidgets('is inactive on unordered list item', (tester) async {
      await tester.pumpWidget(
        buildEditorHarness(
          nodes: [
            ListItemNode.unordered(
              id: 'node-1',
              text: AttributedText('Unordered'),
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

      final numberedBtn = iconButtonWithIcon(Icons.format_list_numbered);
      expect(numberedBtn, findsOneWidget);
      final btnWidget = tester.widget<IconButton>(numberedBtn);
      expect(btnWidget.isSelected, isFalse);
    });
  });

  group('Indent / unindent', () {
    testWidgets('indent button is enabled on a list item', (tester) async {
      await tester.pumpWidget(
        buildEditorHarness(
          nodes: [
            ListItemNode.unordered(id: 'node-1', text: AttributedText('Item')),
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

      final indentBtn = iconButtonWithIcon(Icons.format_indent_increase);
      expect(indentBtn, findsOneWidget);
      expect(tester.widget<IconButton>(indentBtn).onPressed, isNotNull);
    });

    testWidgets('indent button is disabled on a non-list item', (tester) async {
      await tester.pumpWidget(
        buildEditorHarness(
          nodes: [
            ParagraphNode(id: 'node-1', text: AttributedText('Para')),
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

      final indentBtn = iconButtonWithIcon(Icons.format_indent_increase);
      expect(indentBtn, findsOneWidget);
      expect(tester.widget<IconButton>(indentBtn).onPressed, isNull);
    });

    testWidgets('unindent button is enabled on a list item', (tester) async {
      await tester.pumpWidget(
        buildEditorHarness(
          nodes: [
            ListItemNode.unordered(id: 'node-1', text: AttributedText('Item')),
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

      final unindentBtn = iconButtonWithIcon(Icons.format_indent_decrease);
      expect(unindentBtn, findsOneWidget);
      expect(tester.widget<IconButton>(unindentBtn).onPressed, isNotNull);
    });

    testWidgets('unindent button is disabled on a non-list item', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildEditorHarness(
          nodes: [
            ParagraphNode(id: 'node-1', text: AttributedText('Para')),
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

      final unindentBtn = iconButtonWithIcon(Icons.format_indent_decrease);
      expect(unindentBtn, findsOneWidget);
      expect(tester.widget<IconButton>(unindentBtn).onPressed, isNull);
    });

    testWidgets('indent works with multi-node selection of list items', (
      tester,
    ) async {
      final document = MutableDocument(
        nodes: [
          ListItemNode.unordered(id: 'node-1', text: AttributedText('Item 1')),
          ListItemNode.unordered(id: 'node-2', text: AttributedText('Item 2')),
        ],
      );
      final composer = MutableDocumentComposer(
        initialSelection: const DocumentSelection(
          base: DocumentPosition(
            nodeId: 'node-1',
            nodePosition: TextNodePosition(offset: 0),
          ),
          extent: DocumentPosition(
            nodeId: 'node-2',
            nodePosition: TextNodePosition(offset: 6),
          ),
        ),
      );
      final editor = createDefaultDocumentEditor(
        document: document,
        composer: composer,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Expanded(
                  child: SuperEditor(
                    editor: editor,
                    componentBuilders: defaultComponentBuilders,
                  ),
                ),
                NoteToolbar(editor: editor, composer: composer),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final indentBtn = iconButtonWithIcon(Icons.format_indent_increase);
      expect(indentBtn, findsOneWidget);
      expect(tester.widget<IconButton>(indentBtn).onPressed, isNotNull);

      await tester.tap(indentBtn);
      await tester.pumpAndSettle();

      final node1 = document.getNodeById('node-1') as ListItemNode;
      expect(node1.indent, greaterThan(0));
    });
  });
}
