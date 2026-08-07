import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/slash_command_overlay.dart';

class _SlashMenuHarness {
  _SlashMenuHarness() {
    document = MutableDocument(
      nodes: [
        for (var index = 0; index < 12; index++)
          ParagraphNode(
            id: 'prefix-$index',
            text: AttributedText('Prefix $index'),
          ),
        ParagraphNode(id: 'command', text: AttributedText('/')),
      ],
    );
    composer = MutableDocumentComposer();
    editor = createDefaultDocumentEditor(
      document: document,
      composer: composer,
    );
    layoutKey = GlobalKey();
    viewportKey = GlobalKey();
    selectionLayerLinks = SelectionLayerLinks();
    focusNode = FocusNode();
    slashController = SlashCommandController();
  }

  late final MutableDocument document;
  late final MutableDocumentComposer composer;
  late final Editor editor;
  late final GlobalKey layoutKey;
  late final GlobalKey viewportKey;
  late final SelectionLayerLinks selectionLayerLinks;
  late final FocusNode focusNode;
  late final SlashCommandController slashController;

  DocumentSelection selectionAt(int offset) {
    return DocumentSelection.collapsed(
      position: DocumentPosition(
        nodeId: 'command',
        nodePosition: TextNodePosition(offset: offset),
      ),
    );
  }

  Widget build() {
    return MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: KeyedSubtree(
                key: viewportKey,
                child: SuperEditor(
                  editor: editor,
                  focusNode: focusNode,
                  documentLayoutKey: layoutKey,
                  selectionLayerLinks: selectionLayerLinks,
                ),
              ),
            ),
            Positioned.fill(
              child: SlashCommandOverlay(
                editor: editor,
                composer: composer,
                selectionLayerLinks: selectionLayerLinks,
                viewportKey: viewportKey,
                controller: slashController,
                focusNode: focusNode,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void dispose() {
    slashController.dispose();
    focusNode.dispose();
    composer.dispose();
  }
}

void main() {
  testWidgets('keeps the slash menu anchored while filtering', (tester) async {
    final harness = _SlashMenuHarness();
    addTearDown(harness.dispose);

    await tester.pumpWidget(harness.build());
    harness.composer.setSelectionWithReason(harness.selectionAt(1));
    await tester.pumpAndSettle();

    final menuIcon = find.byIcon(Icons.title);
    expect(menuIcon, findsOneWidget);
    final beforeFiltering = tester.getTopLeft(menuIcon);

    harness.editor.execute([
      InsertTextRequest(
        documentPosition: DocumentPosition(
          nodeId: 'command',
          nodePosition: const TextNodePosition(offset: 1),
        ),
        textToInsert: 'h',
        attributions: const {},
      ),
    ]);
    harness.composer.setSelectionWithReason(harness.selectionAt(2));
    await tester.pumpAndSettle();

    final afterFiltering = tester.getTopLeft(menuIcon);
    expect(beforeFiltering.dy, greaterThan(180));
    expect(afterFiltering.dy, greaterThan(180));
    expect((afterFiltering.dy - beforeFiltering.dy).abs(), lessThan(20));
  });

  testWidgets('shows grouped commands with list and task conversions', (
    tester,
  ) async {
    final harness = _SlashMenuHarness();
    addTearDown(harness.dispose);

    await tester.pumpWidget(harness.build());
    harness.composer.setSelectionWithReason(harness.selectionAt(1));
    await tester.pumpAndSettle();

    expect(find.text('Estilo'), findsOneWidget);
    expect(find.text('Listas'), findsOneWidget);
    expect(find.text('Tarefa'), findsOneWidget);
    expect(find.text('Lista com marcadores'), findsOneWidget);
    expect(find.text('Lista numerada'), findsOneWidget);
  });

  testWidgets('uses compact slash menu measurements', (tester) async {
    final harness = _SlashMenuHarness();
    addTearDown(harness.dispose);

    await tester.pumpWidget(harness.build());
    harness.composer.setSelectionWithReason(harness.selectionAt(1));
    await tester.pumpAndSettle();

    final menuCard = find.byKey(const ValueKey('slash-command-card'));
    expect(menuCard, findsOneWidget);
    expect(tester.getSize(menuCard).width, 256);
    expect(tester.getSize(menuCard).height, lessThanOrEqualTo(320));

    final titleIcon = tester.widget<Icon>(find.byIcon(Icons.title));
    expect(titleIcon.size, 16);
  });
}
