import 'package:block_editor/block_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(body: SizedBox(width: 400, child: child)),
  );
}

void main() {
  group('BlockCursor — visibility', () {
    testWidgets('no cursor when selection is NoSelection', (tester) async {
      await tester.pumpWidget(
        wrap(
          BlockCursor(
            blockId: 'b1',
            delta: TextDelta.fromPlainText('hello'),
            selection: EditorSelection.none,
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('no cursor when selection is ExpandedSelection', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          BlockCursor(
            blockId: 'b1',
            delta: TextDelta.fromPlainText('hello'),
            selection: const ExpandedSelection(
              anchor: SelectionPoint(blockId: 'b1', offset: 0),
              focus: SelectionPoint(blockId: 'b1', offset: 5),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('no cursor when CollapsedSelection is for different block', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          BlockCursor(
            blockId: 'b1',
            delta: TextDelta.fromPlainText('hello'),
            selection: const CollapsedSelection(
              SelectionPoint(blockId: 'b2', offset: 0),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'renders without error when CollapsedSelection matches blockId',
      (tester) async {
        await tester.pumpWidget(
          wrap(
            BlockCursor(
              blockId: 'b1',
              delta: TextDelta.fromPlainText('hello'),
              selection: const CollapsedSelection(
                SelectionPoint(blockId: 'b1', offset: 2),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('no cursor when offset is -1', (tester) async {
      await tester.pumpWidget(
        wrap(
          BlockCursor(
            blockId: 'b1',
            delta: TextDelta.fromPlainText('hello'),
            selection: const CollapsedSelection(
              SelectionPoint(blockId: 'b1', offset: -1),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('BlockCursor — external animation', () {
    testWidgets('accepts external animation without error', (tester) async {
      final controller = AnimationController(
        vsync: tester,
        duration: const Duration(milliseconds: 600),
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        wrap(
          BlockCursor(
            blockId: 'b1',
            delta: TextDelta.fromPlainText('hello'),
            selection: const CollapsedSelection(
              SelectionPoint(blockId: 'b1', offset: 2),
            ),
            animation: controller,
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders at full opacity when animation value is 1.0', (
      tester,
    ) async {
      final controller = AnimationController(
        vsync: tester,
        duration: const Duration(milliseconds: 600),
      );
      addTearDown(controller.dispose);
      controller.value = 1.0;

      await tester.pumpWidget(
        wrap(
          BlockCursor(
            blockId: 'b1',
            delta: TextDelta.fromPlainText('hello'),
            selection: const CollapsedSelection(
              SelectionPoint(blockId: 'b1', offset: 2),
            ),
            animation: controller,
            cursorColor: const Color(0xFF000000),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders at zero opacity when animation value is 0.0', (
      tester,
    ) async {
      final controller = AnimationController(
        vsync: tester,
        duration: const Duration(milliseconds: 600),
      );
      addTearDown(controller.dispose);
      controller.value = 0.0;

      await tester.pumpWidget(
        wrap(
          BlockCursor(
            blockId: 'b1',
            delta: TextDelta.fromPlainText('hello'),
            selection: const CollapsedSelection(
              SelectionPoint(blockId: 'b1', offset: 2),
            ),
            animation: controller,
            cursorColor: const Color(0xFF000000),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('BlockCursor — default animation', () {
    testWidgets('renders without error with default animation', (tester) async {
      await tester.pumpWidget(
        wrap(
          BlockCursor(
            blockId: 'b1',
            delta: TextDelta.fromPlainText('hello'),
            selection: const CollapsedSelection(
              SelectionPoint(blockId: 'b1', offset: 2),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('custom blinkDuration is accepted without error', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          BlockCursor(
            blockId: 'b1',
            delta: TextDelta.fromPlainText('hello'),
            selection: const CollapsedSelection(
              SelectionPoint(blockId: 'b1', offset: 2),
            ),
            blinkDuration: const Duration(milliseconds: 800),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('BlockCursor — empty delta', () {
    testWidgets('renders without error on empty delta', (tester) async {
      await tester.pumpWidget(
        wrap(
          BlockCursor(
            blockId: 'b1',
            delta: TextDelta.fromPlainText(''),
            selection: const CollapsedSelection(
              SelectionPoint(blockId: 'b1', offset: 0),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('BlockCursor — child forwarding', () {
    testWidgets('custom child is rendered', (tester) async {
      await tester.pumpWidget(
        wrap(
          BlockCursor(
            blockId: 'b1',
            delta: TextDelta.fromPlainText('hello'),
            selection: EditorSelection.none,
            child: const Text('custom child'),
          ),
        ),
      );
      expect(find.text('custom child'), findsOneWidget);
    });
  });
}
