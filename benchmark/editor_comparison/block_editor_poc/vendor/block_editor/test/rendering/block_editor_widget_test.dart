import 'package:block_editor/block_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

BlockNode paragraph({String? id, String text = ''}) => BlockNode(
  id: id,
  type: BlockTypes.paragraph,
  delta: TextDelta.fromPlainText(text),
);

Widget wrap(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

void main() {
  late BlockController controller;

  setUp(() {
    controller = BlockController(
      document: BlockDocument([
        paragraph(id: 'b1', text: 'First'),
        paragraph(id: 'b2', text: 'Second'),
        paragraph(id: 'b3', text: 'Third'),
      ]),
    );
  });

  tearDown(() => controller.dispose());

  group('BlockEditorWidget — rendering', () {
    testWidgets('renders all blocks', (tester) async {
      await tester.pumpWidget(wrap(BlockEditorWidget(controller: controller)));
      expect(find.byType(BlockRenderer), findsNWidgets(3));
    });

    testWidgets('renders without error on empty document', (tester) async {
      final empty = BlockController(document: const BlockDocument([]));
      addTearDown(empty.dispose);
      await tester.pumpWidget(wrap(BlockEditorWidget(controller: empty)));
      expect(tester.takeException(), isNull);
    });

    testWidgets('rebuilds when document changes', (tester) async {
      await tester.pumpWidget(wrap(BlockEditorWidget(controller: controller)));
      controller.append(paragraph(id: 'b4', text: 'Fourth'));
      await tester.pump();
      expect(find.byType(BlockRenderer), findsNWidgets(4));
    });
  });

  group('BlockEditorWidget — readOnly', () {
    testWidgets('readOnly mode renders all blocks', (tester) async {
      await tester.pumpWidget(
        wrap(BlockEditorWidget(controller: controller, readOnly: true)),
      );
      expect(find.byType(BlockRenderer), findsNWidgets(3));
    });

    testWidgets('readOnly mode suppresses selection on tap', (tester) async {
      await tester.pumpWidget(
        wrap(BlockEditorWidget(controller: controller, readOnly: true)),
      );
      await tester.tap(find.text('First', findRichText: true));
      await tester.pump();
      expect(controller.selection, isA<NoSelection>());
    });
  });

  group('BlockEditorWidget — event dispatch', () {
    testWidgets('tap sets CollapsedSelection on controller', (tester) async {
      await tester.pumpWidget(wrap(BlockEditorWidget(controller: controller)));
      await tester.tap(find.text('First', findRichText: true));
      await tester.pump();
      expect(controller.selection, isA<CollapsedSelection>());
      expect((controller.selection as CollapsedSelection).point.blockId, 'b1');
    });

    testWidgets('checkbox toggle updates checked attribute', (tester) async {
      final todoController = BlockController(
        document: BlockDocument([
          BlockNode(
            id: 't1',
            type: BlockTypes.todo,
            attributes: {'checked': false},
            delta: TextDelta.fromPlainText('task'),
          ),
        ]),
      );
      addTearDown(todoController.dispose);
      await tester.pumpWidget(
        wrap(BlockEditorWidget(controller: todoController)),
      );
      await tester.tap(find.byType(Container).first);
      await tester.pump();
      expect(
        todoController.document.blocks.first.attributes['checked'],
        isTrue,
      );
    });
  });

  group('BlockEditorWidget — keyboard shortcuts', () {
    testWidgets('Ctrl+A triggers selectAll', (tester) async {
      await tester.pumpWidget(wrap(BlockEditorWidget(controller: controller)));
      await tester.tap(find.text('First', findRichText: true));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(controller.selection, isA<ExpandedSelection>());
    });

    testWidgets('Ctrl+Z triggers undo', (tester) async {
      controller.append(paragraph(id: 'b4', text: 'Fourth'));
      await tester.pumpWidget(wrap(BlockEditorWidget(controller: controller)));
      await tester.tap(find.text('First', findRichText: true));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(controller.document.blocks.length, 3);
    });

    testWidgets('Escape clears selection', (tester) async {
      controller.collapseSelection('b1', 0);
      await tester.pumpWidget(wrap(BlockEditorWidget(controller: controller)));
      await tester.tap(find.text('First', findRichText: true));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(controller.selection, isA<NoSelection>());
    });

    testWidgets('keyboard shortcuts are ignored in readOnly mode', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(BlockEditorWidget(controller: controller, readOnly: true)),
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(controller.selection, isA<NoSelection>());
    });
  });

  group('BlockEditorWidget — numbered list ordinal', () {
    testWidgets('consecutive numbered list items get sequential ordinals', (
      tester,
    ) async {
      final numberedController = BlockController(
        document: BlockDocument([
          BlockNode(
            id: 'n1',
            type: BlockTypes.numberedList,
            delta: TextDelta.fromPlainText('one'),
          ),
          BlockNode(
            id: 'n2',
            type: BlockTypes.numberedList,
            delta: TextDelta.fromPlainText('two'),
          ),
          BlockNode(
            id: 'n3',
            type: BlockTypes.numberedList,
            delta: TextDelta.fromPlainText('three'),
          ),
        ]),
      );
      addTearDown(numberedController.dispose);
      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 400,
            height: 600,
            child: BlockEditorWidget(controller: numberedController),
          ),
        ),
      );
      final widgets = tester
          .widgetList<NumberedListWidget>(find.byType(NumberedListWidget))
          .toList();
      expect(widgets[0].number, 1);
      expect(widgets[1].number, 2);
      expect(widgets[2].number, 3);
    });

    testWidgets('non-numbered block resets counter', (tester) async {
      final mixedController = BlockController(
        document: BlockDocument([
          BlockNode(
            id: 'n1',
            type: BlockTypes.numberedList,
            delta: TextDelta.fromPlainText('one'),
          ),
          paragraph(id: 'p1', text: 'break'),
          BlockNode(
            id: 'n2',
            type: BlockTypes.numberedList,
            delta: TextDelta.fromPlainText('restart'),
          ),
        ]),
      );
      addTearDown(mixedController.dispose);
      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 400,
            height: 600,
            child: BlockEditorWidget(controller: mixedController),
          ),
        ),
      );
      final widgets = tester
          .widgetList<NumberedListWidget>(find.byType(NumberedListWidget))
          .toList();
      expect(widgets[0].number, 1);
      expect(widgets[1].number, 1);
    });
  });
}
