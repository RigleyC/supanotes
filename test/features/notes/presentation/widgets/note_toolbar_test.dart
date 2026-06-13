import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';
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
}
