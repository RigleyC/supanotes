import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/custom_list_item_component.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/custom_task_component.dart';
import 'package:supanotes/shared/widgets/app_task_checkbox.dart';
import 'package:super_editor/super_editor.dart';

void main() {
  test('uses one font-based indentation unit', () {
    expect(
      noteEditorIndentUnit(const TextStyle(fontSize: 16)),
      closeTo(38.4, 0.001),
    );
  });

  test('keeps the marker gap and advances one unit per list level', () {
    const textStyle = TextStyle(fontSize: 16);

    expect(noteEditorListIndentCalculator(textStyle, 0, 4), closeTo(12, 0.001));
    expect(
      noteEditorListIndentCalculator(textStyle, 1, 4),
      closeTo(50.4, 0.001),
    );
  });

  test('uses the default text size when style has no font size', () {
    expect(noteEditorIndentUnit(const TextStyle()), closeTo(38.4, 0.001));
  });

  testWidgets('builds unordered and ordered lists with the local builder', (
    tester,
  ) async {
    final document = MutableDocument(
      nodes: [
        ListItemNode.unordered(id: 'bullet', text: AttributedText('Bullet')),
        ListItemNode.ordered(id: 'number', text: AttributedText('Number')),
      ],
    );
    final editor = createDefaultDocumentEditor(document: document);

    await tester.pumpWidget(
      MaterialApp(
        home: SuperEditor(
          editor: editor,
          componentBuilders: const [CustomListItemComponentBuilder()],
        ),
      ),
    );

    expect(find.byType(UnorderedListItemComponent), findsOneWidget);
    expect(find.byType(OrderedListItemComponent), findsOneWidget);
  });

  testWidgets('starts root markers at the editor content edge', (tester) async {
    final document = MutableDocument(
      nodes: [
        ListItemNode.unordered(id: 'bullet', text: AttributedText('Bullet')),
        ListItemNode.ordered(id: 'number', text: AttributedText('Number')),
      ],
    );
    final editor = createDefaultDocumentEditor(document: document);

    await tester.pumpWidget(
      MaterialApp(
        home: SuperEditor(
          editor: editor,
          componentBuilders: const [CustomListItemComponentBuilder()],
        ),
      ),
    );

    expect(
      tester.getTopLeft(find.byKey(const ValueKey('unordered-list-marker'))).dx,
      closeTo(
        tester.getTopLeft(find.byType(UnorderedListItemComponent)).dx,
        0.001,
      ),
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('ordered-list-marker'))).dx,
      closeTo(
        tester.getTopLeft(find.byType(OrderedListItemComponent)).dx,
        0.001,
      ),
    );
  });

  testWidgets('keeps list markers 8px from their text', (tester) async {
    final document = MutableDocument(
      nodes: [
        ListItemNode.unordered(id: 'bullet', text: AttributedText('Bullet')),
        ListItemNode.ordered(id: 'number', text: AttributedText('Number')),
      ],
    );
    final editor = createDefaultDocumentEditor(document: document);

    await tester.pumpWidget(
      MaterialApp(
        home: SuperEditor(
          editor: editor,
          componentBuilders: const [CustomListItemComponentBuilder()],
        ),
      ),
    );

    final bulletGlyph = find.descendant(
      of: find.byType(UnorderedListItemComponent),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.constraints?.minWidth == 4 &&
            widget.constraints?.maxWidth == 4 &&
            widget.constraints?.minHeight == 4 &&
            widget.constraints?.maxHeight == 4,
      ),
    );
    final bulletText = tester.getTopLeft(
      find.descendant(
        of: find.byType(UnorderedListItemComponent),
        matching: find.byType(TextComponent),
      ),
    );
    final numberGlyph = find.descendant(
      of: find.byType(OrderedListItemComponent),
      matching: find.text('1.'),
    );
    final numberText = tester.getTopLeft(
      find.descendant(
        of: find.byType(OrderedListItemComponent),
        matching: find.byType(TextComponent),
      ),
    );

    final bulletGlyphTopLeft = tester.getTopLeft(bulletGlyph);
    final numberGlyphTopLeft = tester.getTopLeft(numberGlyph);
    expect(
      bulletText.dx - bulletGlyphTopLeft.dx - tester.getSize(bulletGlyph).width,
      closeTo(8, 0.001),
    );
    expect(
      numberText.dx - numberGlyphTopLeft.dx - tester.getSize(numberGlyph).width,
      closeTo(8, 0.001),
    );
  });

  testWidgets('moves nested list markers by one indentation unit', (
    tester,
  ) async {
    final document = MutableDocument(
      nodes: [
        ListItemNode.unordered(id: 'root', text: AttributedText('Root')),
        ListItemNode.unordered(
          id: 'nested',
          text: AttributedText('Nested'),
          indent: 1,
        ),
      ],
    );
    final editor = createDefaultDocumentEditor(document: document);

    await tester.pumpWidget(
      MaterialApp(
        home: SuperEditor(
          editor: editor,
          componentBuilders: const [CustomListItemComponentBuilder()],
        ),
      ),
    );

    final markers = find.descendant(
      of: find.byType(UnorderedListItemComponent),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.constraints?.minWidth == 4 &&
            widget.constraints?.maxWidth == 4 &&
            widget.constraints?.minHeight == 4 &&
            widget.constraints?.maxHeight == 4,
      ),
    );
    expect(markers, findsNWidgets(2));
    expect(
      tester.getTopLeft(markers.at(1)).dx - tester.getTopLeft(markers.at(0)).dx,
      closeTo(noteEditorIndentUnit(const TextStyle(fontSize: 18)), 0.001),
    );
  });

  testWidgets('moves nested task checkbox by one indentation unit', (
    tester,
  ) async {
    final document = MutableDocument(
      nodes: [
        TaskNode(
          id: 'task-1',
          text: AttributedText('Parent'),
          isComplete: false,
        ),
        TaskNode(
          id: 'task-2',
          text: AttributedText('Child'),
          isComplete: false,
          indent: 1,
        ),
      ],
    );
    final editor = createDefaultDocumentEditor(document: document);

    await tester.pumpWidget(
      MaterialApp(
        home: SuperEditor(
          editor: editor,
          componentBuilders: [CustomTaskComponentBuilder()],
        ),
      ),
    );

    final checkboxes = find.byType(AppTaskCheckbox);
    expect(checkboxes, findsNWidgets(2));
    final firstX = tester.getTopLeft(checkboxes.at(0)).dx;
    final secondX = tester.getTopLeft(checkboxes.at(1)).dx;
    expect(secondX - firstX, closeTo(43.2, 0.001));
  });

  testWidgets(
    'starts the root checkbox at the block edge with an 8px text gap',
    (tester) async {
      final document = MutableDocument(
        nodes: [
          TaskNode(
            id: 'task-1',
            text: AttributedText('Task'),
            isComplete: false,
          ),
        ],
      );
      final editor = createDefaultDocumentEditor(document: document);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SuperEditor(
              editor: editor,
              componentBuilders: [CustomTaskComponentBuilder()],
            ),
          ),
        ),
      );

      final componentX = tester.getTopLeft(find.byType(CustomTaskComponent)).dx;
      final checkbox = find.byType(AppTaskCheckbox);
      final checkboxBox = tester.getTopLeft(checkbox);
      final textBox = tester.getTopLeft(find.byType(TextComponent));

      expect(checkboxBox.dx, closeTo(componentX, 0.001));
      expect(tester.getSize(checkbox).width, 20);
      expect(textBox.dx - checkboxBox.dx, 28);
    },
  );
}
