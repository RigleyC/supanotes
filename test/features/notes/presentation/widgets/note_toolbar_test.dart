import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';
import 'package:supanotes/features/notes/presentation/widgets/custom_task_component.dart';
import 'package:supanotes/features/notes/presentation/widgets/note_toolbar.dart';

Widget buildEditorHarness({
  required List<DocumentNode> nodes,
  DocumentSelection? selection,
  bool positionAtBottom = false,
}) {
  final document = MutableDocument(nodes: nodes);
  final composer = MutableDocumentComposer(initialSelection: selection);
  final editor = createDefaultDocumentEditor(
    document: document,
    composer: composer,
  );

  return MaterialApp(
    home: Scaffold(
      body: positionAtBottom
          ? Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: NoteToolbar(editor: editor, composer: composer),
                ),
              ],
            )
          : NoteToolbar(editor: editor, composer: composer),
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

/// Finds the toolbar button that contains the given [IconData].
Finder iconButtonWithIcon(IconData icon) {
  return find.ancestor(
    of: find.byIcon(icon),
    matching: find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == '_ToolbarButton',
    ),
  );
}

Finder listPopoverFinder() {
  return find.byWidgetPredicate(
    (widget) => widget.runtimeType.toString() == '_ToolbarListPopover',
  );
}

Future<void> openListMenu(WidgetTester tester) async {
  await tester.tap(listPopoverFinder());
  await tester.pumpAndSettle();
  expect(find.bySemanticsLabel('Lista com marcadores'), findsOneWidget);
  expect(find.bySemanticsLabel('Lista numerada'), findsOneWidget);
  expect(find.bySemanticsLabel('Checklist'), findsOneWidget);
}

Future<void> selectListOption(WidgetTester tester, String label) async {
  await openListMenu(tester);
  final semanticLabel = switch (label) {
    'Bullet List' => 'Lista com marcadores',
    'Numbered List' => 'Lista numerada',
    'Checklist' => 'Checklist',
    _ => throw ArgumentError.value(label, 'label'),
  };
  await tester.tap(find.bySemanticsLabel(semanticLabel));
  await tester.pumpAndSettle();
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
                CustomTaskComponentBuilder(),
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
  group('List menu trigger state', () {
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

      final listPopover = listPopoverFinder();
      expect(listPopover, findsOneWidget);

      final button = tester.widget(listPopover);
      expect((button as dynamic).isTask, isFalse);
      expect(
        (tester.widget(iconButtonWithIcon(Icons.format_list_bulleted))
                as dynamic)
            .isActive,
        isFalse,
      );
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

      final listPopover = listPopoverFinder();
      expect(listPopover, findsOneWidget);

      final button = tester.widget(listPopover);
      expect((button as dynamic).isTask, isTrue);
      expect(
        (tester.widget(iconButtonWithIcon(Icons.check_box_outlined)) as dynamic)
            .isActive,
        isTrue,
      );
    });

    testWidgets('opens with the three list options and dismisses outside', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildEditorHarness(
          nodes: [ParagraphNode(id: 'node-1', text: AttributedText('Text'))],
          selection: const DocumentSelection.collapsed(
            position: DocumentPosition(
              nodeId: 'node-1',
              nodePosition: TextNodePosition(offset: 0),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await openListMenu(tester);

      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Opções de lista'), findsNothing);
    });

    testWidgets('dismisses with Escape', (tester) async {
      await tester.pumpWidget(
        buildEditorHarness(
          nodes: [ParagraphNode(id: 'node-1', text: AttributedText('Text'))],
          selection: const DocumentSelection.collapsed(
            position: DocumentPosition(
              nodeId: 'node-1',
              nodePosition: TextNodePosition(offset: 0),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await openListMenu(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Opções de lista'), findsNothing);
    });

    testWidgets('constrains the menu on a short viewport', (tester) async {
      tester.view.physicalSize = const Size(240, 180);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        buildEditorHarness(
          nodes: [ParagraphNode(id: 'node-1', text: AttributedText('Text'))],
          selection: const DocumentSelection.collapsed(
            position: DocumentPosition(
              nodeId: 'node-1',
              nodePosition: TextNodePosition(offset: 0),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await openListMenu(tester);

      expect(tester.takeException(), isNull);
    });

    testWidgets('applies the option to the selection captured on open', (
      tester,
    ) async {
      final document = MutableDocument(
        nodes: [
          ParagraphNode(id: 'node-1', text: AttributedText('First')),
          ParagraphNode(id: 'node-2', text: AttributedText('Second')),
        ],
      );
      final firstSelection = const DocumentSelection.collapsed(
        position: DocumentPosition(
          nodeId: 'node-1',
          nodePosition: TextNodePosition(offset: 0),
        ),
      );
      final secondSelection = const DocumentSelection.collapsed(
        position: DocumentPosition(
          nodeId: 'node-2',
          nodePosition: TextNodePosition(offset: 0),
        ),
      );
      final composer = MutableDocumentComposer(
        initialSelection: firstSelection,
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
                      CustomTaskComponentBuilder(),
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

      await openListMenu(tester);
      composer.setSelectionWithReason(secondSelection);
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Lista com marcadores'));
      await tester.pumpAndSettle();

      expect(document.getNodeById('node-1'), isA<ListItemNode>());
      expect(document.getNodeById('node-2'), isA<ParagraphNode>());
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
                      CustomTaskComponentBuilder(),
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

      await selectListOption(tester, 'Checklist');

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
                      CustomTaskComponentBuilder(),
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

      await selectListOption(tester, 'Checklist');

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
                      CustomTaskComponentBuilder(),
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

      await selectListOption(tester, 'Checklist');

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
                      CustomTaskComponentBuilder(),
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

      await selectListOption(tester, 'Checklist');

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
                      CustomTaskComponentBuilder(),
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

      await selectListOption(tester, 'Bullet List');

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
                      CustomTaskComponentBuilder(),
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

      await selectListOption(tester, 'Numbered List');

      expect(document.first, isA<ListItemNode>());
      final item = document.first as ListItemNode;
      expect(item.text.toPlainText(), 'Buy milk');
      expect(item.type, ListItemType.ordered);
    });
  });

  group('_setBlockType', () {
    Future<void> openFormatPopup(WidgetTester tester) async {
      await tester.tap(iconButtonWithIcon(Icons.text_format));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Opções de formatação'), findsOneWidget);
    }

    // The format popup opens above the toolbar and is tall (heading previews
    // use headline-sized fonts). The default 800×600 test surface is shorter
    // than any real phone in portrait, so the popup's H1 item can end up
    // above the viewport. Use a realistic mobile viewport for these tests.

    testWidgets('converts ListItemNode to H1', (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

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
            body: Stack(
              children: [
                Positioned.fill(
                  child: SuperEditor(
                    editor: editor,
                    componentBuilders: defaultComponentBuilders,
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: NoteToolbar(editor: editor, composer: composer),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await openFormatPopup(tester);
      await tester.tap(find.bySemanticsLabel('Título 1'));
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
                      CustomTaskComponentBuilder(),
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

      await openFormatPopup(tester);
      await tester.tap(find.bySemanticsLabel('Título 2'));
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
                      CustomTaskComponentBuilder(),
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

      await openFormatPopup(tester);
      await tester.tap(find.bySemanticsLabel('Citação'));
      await tester.pumpAndSettle();

      expect(document.first, isA<ParagraphNode>());
      final para = document.first as ParagraphNode;
      expect(para.text.toPlainText(), 'Quoted text');
      expect(para.getMetadataValue('blockType'), blockquoteAttribution);
    });
  });

  group('List menu trigger active state', () {
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
      final btnWidget = tester.widget(numberedBtn);
      expect((btnWidget as dynamic).isActive, isTrue);
    });

    testWidgets('is active on unordered list item', (tester) async {
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

      final bulletedBtn = iconButtonWithIcon(Icons.format_list_bulleted);
      expect(bulletedBtn, findsOneWidget);
      final btnWidget = tester.widget(bulletedBtn);
      expect((btnWidget as dynamic).isActive, isTrue);
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
      expect((tester.widget(indentBtn) as dynamic).onPressed, isNotNull);
    });

    testWidgets('indent button is not present on a non-list item', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildEditorHarness(
          nodes: [ParagraphNode(id: 'node-1', text: AttributedText('Para'))],
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
      expect(indentBtn, findsNothing);
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
      expect((tester.widget(unindentBtn) as dynamic).onPressed, isNotNull);
    });

    testWidgets('unindent button is not present on a non-list item', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildEditorHarness(
          nodes: [ParagraphNode(id: 'node-1', text: AttributedText('Para'))],
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
      expect(unindentBtn, findsNothing);
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
      expect((tester.widget(indentBtn) as dynamic).onPressed, isNotNull);

      await tester.tap(indentBtn);
      await tester.pumpAndSettle();

      final node1 = document.getNodeById('node-1') as ListItemNode;
      expect(node1.indent, greaterThan(0));
    });
  });

  group('Contextual Selection Toolbar', () {
    testWidgets(
      'updates task state after a document change without moving the cursor',
      (tester) async {
        final document = MutableDocument(
          nodes: [
            ParagraphNode(id: 'node-1', text: AttributedText('Task text')),
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
              body: NoteToolbar(editor: editor, composer: composer),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final listButton = iconButtonWithIcon(Icons.format_list_bulleted);
        expect((tester.widget(listButton) as dynamic).isActive, isFalse);

        editor.execute([ConvertParagraphToTaskRequest(nodeId: 'node-1')]);
        await tester.pumpAndSettle();

        final taskButton = iconButtonWithIcon(Icons.check_box_outlined);
        expect((tester.widget(taskButton) as dynamic).isActive, isTrue);
      },
    );

    testWidgets('shows inline actions in the format overlay', (tester) async {
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

      expect(find.byIcon(Icons.format_bold), findsNothing);
      expect(find.byIcon(Icons.format_italic), findsNothing);
      expect(find.byIcon(Icons.format_strikethrough), findsNothing);

      await tester.tap(iconButtonWithIcon(Icons.text_format));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.format_bold), findsOneWidget);
      expect(
        (tester.widget(iconButtonWithIcon(Icons.format_bold)) as dynamic)
            .onPressed,
        isNull,
      );
    });

    testWidgets('shows bold/italic/strikethrough when text is selected', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildEditorHarness(
          nodes: [ParagraphNode(id: 'node-1', text: AttributedText('Hello'))],
          selection: const DocumentSelection(
            base: DocumentPosition(
              nodeId: 'node-1',
              nodePosition: TextNodePosition(offset: 0),
            ),
            extent: DocumentPosition(
              nodeId: 'node-1',
              nodePosition: TextNodePosition(offset: 5),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(iconButtonWithIcon(Icons.text_format));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.format_bold), findsOneWidget);
      expect(find.byIcon(Icons.format_italic), findsOneWidget);
      expect(find.byIcon(Icons.format_strikethrough), findsOneWidget);
    });

    testWidgets(
      'does not mark bold active when it starts after the selection',
      (tester) async {
        final spans = AttributedSpans()
          ..addAttribution(newAttribution: boldAttribution, start: 5, end: 5);
        await tester.pumpWidget(
          buildEditorHarness(
            nodes: [
              ParagraphNode(
                id: 'node-1',
                text: AttributedText('Hello!', spans),
              ),
            ],
            selection: const DocumentSelection(
              base: DocumentPosition(
                nodeId: 'node-1',
                nodePosition: TextNodePosition(offset: 0),
              ),
              extent: DocumentPosition(
                nodeId: 'node-1',
                nodePosition: TextNodePosition(offset: 5),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(iconButtonWithIcon(Icons.text_format));
        await tester.pumpAndSettle();

        final boldButton = iconButtonWithIcon(Icons.format_bold);
        expect((tester.widget(boldButton) as dynamic).isActive, isFalse);
      },
    );

    testWidgets('keeps the format overlay open after applying a style', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        buildEditorHarness(
          positionAtBottom: true,
          nodes: [ParagraphNode(id: 'node-1', text: AttributedText('Hello'))],
          selection: const DocumentSelection(
            base: DocumentPosition(
              nodeId: 'node-1',
              nodePosition: TextNodePosition(offset: 0),
            ),
            extent: DocumentPosition(
              nodeId: 'node-1',
              nodePosition: TextNodePosition(offset: 5),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(iconButtonWithIcon(Icons.text_format));
      await tester.pumpAndSettle();

      await tester.tap(iconButtonWithIcon(Icons.format_bold));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Opções de formatação'), findsOneWidget);
      expect(
        (tester.widget(iconButtonWithIcon(Icons.format_bold)) as dynamic)
            .isActive,
        isTrue,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Opções de formatação'), findsNothing);
    });

    testWidgets('format and list overlays fit their content', (tester) async {
      await tester.pumpWidget(
        buildEditorHarness(
          nodes: [ParagraphNode(id: 'node-1', text: AttributedText('Hello'))],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(iconButtonWithIcon(Icons.text_format));
      await tester.pumpAndSettle();
      final formatSize = tester.getSize(
        find.byWidgetPredicate(
          (widget) => widget.runtimeType.toString() == '_FormattingMenu',
        ),
      );
      expect(formatSize.height, lessThanOrEqualTo(44));
      expect(formatSize.width, lessThan(300));

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.tap(listPopoverFinder());
      await tester.pumpAndSettle();
      final listSize = tester.getSize(
        find.byWidgetPredicate(
          (widget) => widget.runtimeType.toString() == '_ListFormatMenu',
        ),
      );
      expect(listSize.height, lessThanOrEqualTo(44));
      expect(listSize.width, lessThan(140));
    });

    testWidgets('focuses the editor and creates a new block at the end', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final document = MutableDocument(
        nodes: [
          ParagraphNode(id: 'node-1', text: AttributedText('Existing text')),
          TaskNode(
            id: 'node-2',
            text: AttributedText('Final task'),
            isComplete: false,
          ),
        ],
      );
      final composer = MutableDocumentComposer();
      final editor = createDefaultDocumentEditor(
        document: document,
        composer: composer,
      );
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Focus(
                    focusNode: focusNode,
                    child: NoteToolbar(
                      editor: editor,
                      composer: composer,
                      focusNode: focusNode,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(iconButtonWithIcon(Icons.text_format));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Título 1'));
      await tester.pumpAndSettle();

      expect(focusNode.hasFocus, isTrue);
      expect(composer.selection?.extent.nodeId, isNot('node-2'));
      final newNode = document.last;
      expect(newNode, isA<ParagraphNode>());
      expect(newNode.id, isNot('node-2'));
      expect(composer.selection?.extent.nodeId, newNode.id);
      expect(document.getNodeById('node-2'), isA<TaskNode>());
      expect(
        (newNode as ParagraphNode).getMetadataValue('blockType'),
        header1Attribution,
      );
    });

    testWidgets('does not reuse a cleared selection for a new block', (
      tester,
    ) async {
      final document = MutableDocument(
        nodes: [
          ParagraphNode(id: 'node-1', text: AttributedText('Existing text')),
          TaskNode(
            id: 'node-2',
            text: AttributedText('Final task'),
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
            body: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: NoteToolbar(editor: editor, composer: composer),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      composer.clearSelection();
      await tester.pump();
      await tester.tap(iconButtonWithIcon(Icons.text_format));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Título 1'));
      await tester.pumpAndSettle();

      expect(
        (document.getNodeById('node-1') as ParagraphNode).getMetadataValue(
          'blockType',
        ),
        isNot(header1Attribution),
      );
      expect(document.last.id, isNot('node-2'));
      expect(document.last, isA<ParagraphNode>());
      expect(
        (document.last as ParagraphNode).getMetadataValue('blockType'),
        header1Attribution,
      );
    });
  });
}
