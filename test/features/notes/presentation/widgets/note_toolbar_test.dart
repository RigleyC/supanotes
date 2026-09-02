import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/note_toolbar.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/note_toolbar_button.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/note_toolbar_state.dart';
import 'package:super_editor/super_editor.dart';

/// Pumps a bare [NoteToolbar] with the given nodes and initial selection.
/// Returns the document, composer, and editor for assertions and commands.
({Editor editor, MutableDocument document, MutableDocumentComposer composer})
buildToolbarHarness({
  required List<DocumentNode> nodes,
  DocumentSelection? selection,
}) {
  final document = MutableDocument(nodes: nodes);
  final composer = MutableDocumentComposer(initialSelection: selection);
  final editor = createDefaultDocumentEditor(
    document: document,
    composer: composer,
  );
  return (editor: editor, document: document, composer: composer);
}

Future<void> pumpToolbar(
  WidgetTester tester, {
  required List<DocumentNode> nodes,
  DocumentSelection? selection,
  bool disableAnimations = false,
}) async {
  final harness = buildToolbarHarness(nodes: nodes, selection: selection);
  Widget child = NoteToolbar(
    editor: harness.editor,
    composer: harness.composer,
  );
  if (disableAnimations) {
    child = MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: child,
    );
  }
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
  await tester.pumpAndSettle();
}

DocumentSelection caretSelection(String nodeId, [int offset = 0]) {
  return DocumentSelection.collapsed(
    position: DocumentPosition(
      nodeId: nodeId,
      nodePosition: TextNodePosition(offset: offset),
    ),
  );
}

Finder iconButtonWithIcon(IconData icon) {
  return find.ancestor(
    of: find.byIcon(icon),
    matching: find.byType(ToolbarButton),
  );
}

void main() {
  test('resolves a shared block type across multiple paragraphs', () {
    final nodes = [
      ParagraphNode(
        id: 'heading-1',
        text: AttributedText('One'),
        metadata: const {'blockType': header2Attribution},
      ),
      ParagraphNode(
        id: 'heading-2',
        text: AttributedText('Two'),
        metadata: const {'blockType': header2Attribution},
      ),
    ];

    expect(resolveSelectedBlockType(nodes), header2Attribution);
  });

  group('normal block-format controls', () {
    testWidgets('shows block controls for a paragraph and hides inline', (
      tester,
    ) async {
      await pumpToolbar(
        tester,
        nodes: [ParagraphNode(id: 'node-1', text: AttributedText('Hello'))],
        selection: caretSelection('node-1'),
      );

      expect(find.bySemanticsLabel('Título 1'), findsOneWidget);
      expect(find.bySemanticsLabel('Título 2'), findsOneWidget);
      expect(find.bySemanticsLabel('Título 3'), findsOneWidget);
      expect(find.bySemanticsLabel('Citação'), findsOneWidget);
      expect(find.bySemanticsLabel('Task'), findsOneWidget);
      expect(find.bySemanticsLabel('Inserir divisor'), findsOneWidget);
      expect(find.bySemanticsLabel('Negrito'), findsNothing);
    });

    testWidgets('converts a paragraph to task from normal toolbar', (
      tester,
    ) async {
      final harness = buildToolbarHarness(
        nodes: [ParagraphNode(id: 'node-1', text: AttributedText('Todo'))],
        selection: caretSelection('node-1'),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NoteToolbar(
              editor: harness.editor,
              composer: harness.composer,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Task'));
      await tester.pumpAndSettle();

      final node = harness.document.getNodeById('node-1');
      expect(node, isA<TaskNode>());
      expect((node! as TaskNode).text.toPlainText(), 'Todo');
    });

    testWidgets('converts a paragraph to H1', (tester) async {
      final harness = buildToolbarHarness(
        nodes: [ParagraphNode(id: 'node-1', text: AttributedText('Heading'))],
        selection: caretSelection('node-1'),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NoteToolbar(
              editor: harness.editor,
              composer: harness.composer,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Título 1'));
      await tester.pumpAndSettle();

      final node = harness.document.getNodeById('node-1')! as ParagraphNode;
      expect(node.getMetadataValue('blockType'), header1Attribution);
    });

    testWidgets('converts a paragraph to H2', (tester) async {
      final harness = buildToolbarHarness(
        nodes: [ParagraphNode(id: 'node-1', text: AttributedText('Heading'))],
        selection: caretSelection('node-1'),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NoteToolbar(
              editor: harness.editor,
              composer: harness.composer,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Título 2'));
      await tester.pumpAndSettle();

      final node = harness.document.getNodeById('node-1')! as ParagraphNode;
      expect(node.getMetadataValue('blockType'), header2Attribution);
    });

    testWidgets('converts a paragraph to H3 and to a blockquote', (
      tester,
    ) async {
      final harness = buildToolbarHarness(
        nodes: [ParagraphNode(id: 'node-1', text: AttributedText('Heading'))],
        selection: caretSelection('node-1'),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NoteToolbar(
              editor: harness.editor,
              composer: harness.composer,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Título 3'));
      await tester.pumpAndSettle();
      expect(
        (harness.document.getNodeById('node-1')! as ParagraphNode)
            .getMetadataValue('blockType'),
        header3Attribution,
      );

      await tester.tap(find.bySemanticsLabel('Citação'));
      await tester.pumpAndSettle();
      expect(
        (harness.document.getNodeById('node-1')! as ParagraphNode)
            .getMetadataValue('blockType'),
        blockquoteAttribution,
      );
    });
  });

  group('contextual controls', () {
    testWidgets('shows inline and list controls when text is selected', (
      tester,
    ) async {
      await pumpToolbar(
        tester,
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
      );

      expect(find.bySemanticsLabel('Negrito'), findsOneWidget);
      expect(find.bySemanticsLabel('Itálico'), findsOneWidget);
      expect(find.bySemanticsLabel('Tachado'), findsOneWidget);
      expect(find.bySemanticsLabel('Lista com marcadores'), findsOneWidget);
      expect(find.bySemanticsLabel('Lista numerada'), findsOneWidget);
      expect(find.bySemanticsLabel('Task'), findsOneWidget);
      expect(find.bySemanticsLabel('Título 1'), findsNothing);
    });

    testWidgets('shows inline controls for a collapsed caret on a list item', (
      tester,
    ) async {
      await pumpToolbar(
        tester,
        nodes: [
          ListItemNode.unordered(id: 'node-1', text: AttributedText('Item')),
        ],
        selection: caretSelection('node-1'),
      );

      expect(find.bySemanticsLabel('Negrito'), findsOneWidget);
      expect(find.bySemanticsLabel('Aumentar recuo'), findsOneWidget);
      expect(find.bySemanticsLabel('Diminuir recuo'), findsOneWidget);
    });

    testWidgets('disables inline actions without a text selection', (
      tester,
    ) async {
      await pumpToolbar(
        tester,
        nodes: [
          ListItemNode.unordered(id: 'node-1', text: AttributedText('Item')),
        ],
        selection: caretSelection('node-1'),
      );

      final bold = tester.widget<ToolbarButton>(
        iconButtonWithIcon(Icons.format_bold),
      );
      expect(bold.onPressed, isNull);
    });

    testWidgets('disables indent and outdent for a paragraph selection', (
      tester,
    ) async {
      await pumpToolbar(
        tester,
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
      );

      final indent = tester.widget<ToolbarButton>(
        iconButtonWithIcon(Icons.format_indent_increase),
      );
      final outdent = tester.widget<ToolbarButton>(
        iconButtonWithIcon(Icons.format_indent_decrease),
      );
      expect(indent.onPressed, isNull);
      expect(outdent.onPressed, isNull);
    });

    testWidgets('enables indent and outdent for a list item caret', (
      tester,
    ) async {
      await pumpToolbar(
        tester,
        nodes: [
          ListItemNode.unordered(id: 'node-1', text: AttributedText('Item')),
        ],
        selection: caretSelection('node-1'),
      );

      final indent = tester.widget<ToolbarButton>(
        iconButtonWithIcon(Icons.format_indent_increase),
      );
      final outdent = tester.widget<ToolbarButton>(
        iconButtonWithIcon(Icons.format_indent_decrease),
      );
      expect(indent.onPressed, isNotNull);
      expect(outdent.onPressed, isNotNull);
    });
  });

  group('command results', () {
    Future<
      ({
        Editor editor,
        MutableDocument document,
        MutableDocumentComposer composer,
      })
    >
    pumpCommand(
      WidgetTester tester, {
      required List<DocumentNode> nodes,
      required DocumentSelection selection,
    }) async {
      final harness = buildToolbarHarness(nodes: nodes, selection: selection);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NoteToolbar(
              editor: harness.editor,
              composer: harness.composer,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return harness;
    }

    testWidgets('applies bold to the selection', (tester) async {
      final harness = await pumpCommand(
        tester,
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
      );

      await tester.tap(find.bySemanticsLabel('Negrito'));
      await tester.pumpAndSettle();

      final text = (harness.document.getNodeById('node-1')! as TextNode).text;
      expect(text.hasAttributionAt(0, attribution: boldAttribution), isTrue);
      expect(text.hasAttributionAt(4, attribution: boldAttribution), isTrue);
    });

    testWidgets('applies italic and strikethrough to the selection', (
      tester,
    ) async {
      DocumentSelection makeSelection() => const DocumentSelection(
        base: DocumentPosition(
          nodeId: 'node-1',
          nodePosition: TextNodePosition(offset: 0),
        ),
        extent: DocumentPosition(
          nodeId: 'node-1',
          nodePosition: TextNodePosition(offset: 5),
        ),
      );
      final harness = await pumpCommand(
        tester,
        nodes: [ParagraphNode(id: 'node-1', text: AttributedText('Hello'))],
        selection: makeSelection(),
      );

      await tester.tap(find.bySemanticsLabel('Itálico'));
      await tester.pumpAndSettle();
      var text = (harness.document.getNodeById('node-1')! as TextNode).text;
      expect(text.hasAttributionAt(2, attribution: italicsAttribution), isTrue);

      harness.composer.setSelectionWithReason(makeSelection());
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Tachado'));
      await tester.pumpAndSettle();
      text = (harness.document.getNodeById('node-1')! as TextNode).text;
      expect(
        text.hasAttributionAt(2, attribution: strikethroughAttribution),
        isTrue,
      );
    });

    testWidgets('converts a paragraph to a bulleted list', (tester) async {
      final harness = await pumpCommand(
        tester,
        nodes: [ParagraphNode(id: 'node-1', text: AttributedText('Item'))],
        selection: caretSelection('node-1'),
      );
      harness.composer.setSelectionWithReason(
        const DocumentSelection(
          base: DocumentPosition(
            nodeId: 'node-1',
            nodePosition: TextNodePosition(offset: 0),
          ),
          extent: DocumentPosition(
            nodeId: 'node-1',
            nodePosition: TextNodePosition(offset: 4),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Lista com marcadores'));
      await tester.pumpAndSettle();

      final node = harness.document.getNodeById('node-1');
      expect(node, isA<ListItemNode>());
      expect((node! as ListItemNode).type, ListItemType.unordered);
    });

    testWidgets('converts a paragraph to a numbered list', (tester) async {
      final harness = await pumpCommand(
        tester,
        nodes: [ParagraphNode(id: 'node-1', text: AttributedText('Item'))],
        selection: caretSelection('node-1'),
      );
      harness.composer.setSelectionWithReason(
        const DocumentSelection(
          base: DocumentPosition(
            nodeId: 'node-1',
            nodePosition: TextNodePosition(offset: 0),
          ),
          extent: DocumentPosition(
            nodeId: 'node-1',
            nodePosition: TextNodePosition(offset: 4),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Lista numerada'));
      await tester.pumpAndSettle();

      final node = harness.document.getNodeById('node-1');
      expect(node, isA<ListItemNode>());
      expect((node! as ListItemNode).type, ListItemType.ordered);
    });

    testWidgets('converts a paragraph to a task', (tester) async {
      final harness = await pumpCommand(
        tester,
        nodes: [ParagraphNode(id: 'node-1', text: AttributedText('Todo'))],
        selection: caretSelection('node-1'),
      );
      harness.composer.setSelectionWithReason(
        const DocumentSelection(
          base: DocumentPosition(
            nodeId: 'node-1',
            nodePosition: TextNodePosition(offset: 0),
          ),
          extent: DocumentPosition(
            nodeId: 'node-1',
            nodePosition: TextNodePosition(offset: 4),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Task'));
      await tester.pumpAndSettle();

      final node = harness.document.getNodeById('node-1');
      expect(node, isA<TaskNode>());
      expect((node! as TaskNode).text.toPlainText(), 'Todo');
    });

    testWidgets('indents and unindents a selected task', (tester) async {
      final harness = await pumpCommand(
        tester,
        nodes: [
          TaskNode(
            id: 'node-1',
            text: AttributedText('Parent'),
            isComplete: false,
          ),
          TaskNode(
            id: 'node-2',
            text: AttributedText('Child'),
            isComplete: false,
          ),
        ],
        selection: caretSelection('node-2'),
      );
      harness.composer.setSelectionWithReason(
        const DocumentSelection(
          base: DocumentPosition(
            nodeId: 'node-2',
            nodePosition: TextNodePosition(offset: 0),
          ),
          extent: DocumentPosition(
            nodeId: 'node-2',
            nodePosition: TextNodePosition(offset: 5),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Aumentar recuo'));
      await tester.pumpAndSettle();
      expect((harness.document.getNodeById('node-2')! as TaskNode).indent, 1);

      await tester.tap(find.bySemanticsLabel('Diminuir recuo'));
      await tester.pumpAndSettle();
      expect((harness.document.getNodeById('node-2')! as TaskNode).indent, 0);
    });
  });

  group('animated shell', () {
    testWidgets('keeps the shell anchored while switching modes', (
      tester,
    ) async {
      final harness = buildToolbarHarness(
        nodes: [ParagraphNode(id: 'node-1', text: AttributedText('Hello'))],
        selection: caretSelection('node-1'),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NoteToolbar(
              editor: harness.editor,
              composer: harness.composer,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Título 1'), findsOneWidget);

      final shellBefore = tester.getTopLeft(
        find.byKey(const ValueKey('note-toolbar-shell')),
      );

      harness.composer.setSelectionWithReason(
        const DocumentSelection(
          base: DocumentPosition(
            nodeId: 'node-1',
            nodePosition: TextNodePosition(offset: 0),
          ),
          extent: DocumentPosition(
            nodeId: 'node-1',
            nodePosition: TextNodePosition(offset: 5),
          ),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(
        tester.getTopLeft(find.byKey(const ValueKey('note-toolbar-shell'))),
        shellBefore,
      );
      expect(find.bySemanticsLabel('Negrito'), findsOneWidget);
      expect(find.bySemanticsLabel('Título 1'), findsNothing);
    });

    testWidgets('with animations disabled exposes the contextual set', (
      tester,
    ) async {
      final harness = buildToolbarHarness(
        nodes: [ParagraphNode(id: 'node-1', text: AttributedText('Hello'))],
        selection: caretSelection('node-1'),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(disableAnimations: true),
              child: NoteToolbar(
                editor: harness.editor,
                composer: harness.composer,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Título 1'), findsOneWidget);

      harness.composer.setSelectionWithReason(
        const DocumentSelection(
          base: DocumentPosition(
            nodeId: 'node-1',
            nodePosition: TextNodePosition(offset: 0),
          ),
          extent: DocumentPosition(
            nodeId: 'node-1',
            nodePosition: TextNodePosition(offset: 5),
          ),
        ),
      );
      await tester.pump();

      expect(find.bySemanticsLabel('Negrito'), findsOneWidget);
      expect(find.bySemanticsLabel('Título 1'), findsNothing);
    });
  });
}
