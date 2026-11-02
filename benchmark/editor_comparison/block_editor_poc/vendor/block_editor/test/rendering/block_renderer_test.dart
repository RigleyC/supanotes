import 'package:block_editor/block_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget wrap(Widget child) {
  return Directionality(textDirection: TextDirection.ltr, child: child);
}

BlockNode node(String type, {Map<String, dynamic>? attributes, String? text}) {
  return BlockNode(
    id: 'b1',
    type: type,
    attributes: attributes,
    delta: text != null ? TextDelta.fromPlainText(text) : null,
  );
}

void main() {
  group('BlockRenderer — built-in block types', () {
    testWidgets('paragraph renders ParagraphWidget', (tester) async {
      await tester.pumpWidget(
        wrap(
          BlockRenderer(
            node: node(BlockTypes.paragraph, text: 'hello'),
            onEvent: (_) {},
          ),
        ),
      );
      expect(find.byType(ParagraphWidget), findsOneWidget);
    });

    testWidgets('heading1 renders H1Widget', (tester) async {
      await tester.pumpWidget(
        wrap(
          BlockRenderer(
            node: node(BlockTypes.heading1, text: 'Title'),
            onEvent: (_) {},
          ),
        ),
      );
      expect(find.byType(H1Widget), findsOneWidget);
    });

    testWidgets('heading2 renders H2Widget', (tester) async {
      await tester.pumpWidget(
        wrap(
          BlockRenderer(
            node: node(BlockTypes.heading2, text: 'Subtitle'),
            onEvent: (_) {},
          ),
        ),
      );
      expect(find.byType(H2Widget), findsOneWidget);
    });

    testWidgets('heading3 renders H3Widget', (tester) async {
      await tester.pumpWidget(
        wrap(
          BlockRenderer(
            node: node(BlockTypes.heading3, text: 'Section'),
            onEvent: (_) {},
          ),
        ),
      );
      expect(find.byType(H3Widget), findsOneWidget);
    });

    testWidgets('bulletList renders BulletListWidget', (tester) async {
      await tester.pumpWidget(
        wrap(
          BlockRenderer(
            node: node(BlockTypes.bulletList, text: 'item'),
            onEvent: (_) {},
          ),
        ),
      );
      expect(find.byType(BulletListWidget), findsOneWidget);
    });

    testWidgets('numberedList renders NumberedListWidget', (tester) async {
      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 400,
            height: 50,
            child: BlockRenderer(
              node: node(BlockTypes.numberedList, text: 'item'),
              onEvent: (_) {},
              number: 2,
            ),
          ),
        ),
      );
      expect(find.byType(NumberedListWidget), findsOneWidget);
    });

    testWidgets('todo renders TodoWidget', (tester) async {
      await tester.pumpWidget(
        wrap(
          BlockRenderer(
            node: node(BlockTypes.todo, text: 'task'),
            onEvent: (_) {},
          ),
        ),
      );
      expect(find.byType(TodoWidget), findsOneWidget);
    });

    testWidgets('quote renders QuoteWidget', (tester) async {
      await tester.pumpWidget(
        wrap(
          BlockRenderer(
            node: node(BlockTypes.quote, text: 'wisdom'),
            onEvent: (_) {},
          ),
        ),
      );
      expect(find.byType(QuoteWidget), findsOneWidget);
    });

    testWidgets('divider renders DividerWidget', (tester) async {
      await tester.pumpWidget(
        wrap(BlockRenderer(node: node(BlockTypes.divider), onEvent: (_) {})),
      );
      expect(find.byType(DividerWidget), findsOneWidget);
    });
  });

  group('BlockRenderer — unknown type', () {
    testWidgets('unknown type renders UnknownBlock', (tester) async {
      await tester.pumpWidget(
        wrap(
          BlockRenderer(
            node: node('custom_plugin_block', text: 'data'),
            onEvent: (_) {},
          ),
        ),
      );
      expect(find.byType(UnknownBlock), findsOneWidget);
    });

    testWidgets('unknown block displays type string', (tester) async {
      await tester.pumpWidget(
        wrap(BlockRenderer(node: node('mystery_type'), onEvent: (_) {})),
      );
      expect(find.text('[unknown block: mystery_type]'), findsOneWidget);
    });
  });

  group('BlockRenderer — number forwarding', () {
    testWidgets('number is forwarded to NumberedListWidget', (tester) async {
      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 400,
            height: 50,
            child: BlockRenderer(
              node: node(BlockTypes.numberedList, text: 'item'),
              onEvent: (_) {},
              number: 5,
            ),
          ),
        ),
      );
      final widget = tester.widget<NumberedListWidget>(
        find.byType(NumberedListWidget),
      );
      expect(widget.number, 5);
    });

    testWidgets('number defaults to 1', (tester) async {
      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 400,
            height: 50,
            child: BlockRenderer(
              node: node(BlockTypes.numberedList, text: 'item'),
              onEvent: (_) {},
            ),
          ),
        ),
      );
      final widget = tester.widget<NumberedListWidget>(
        find.byType(NumberedListWidget),
      );
      expect(widget.number, 1);
    });
  });

  group('BlockRenderer — checked attribute', () {
    testWidgets('checked true is forwarded to TodoWidget', (tester) async {
      await tester.pumpWidget(
        wrap(
          BlockRenderer(
            node: node(
              BlockTypes.todo,
              text: 'task',
              attributes: {'checked': true},
            ),
            onEvent: (_) {},
          ),
        ),
      );
      final widget = tester.widget<TodoWidget>(find.byType(TodoWidget));
      expect(widget.checked, isTrue);
    });

    testWidgets('checked defaults to false when absent', (tester) async {
      await tester.pumpWidget(
        wrap(
          BlockRenderer(
            node: node(BlockTypes.todo, text: 'task'),
            onEvent: (_) {},
          ),
        ),
      );
      final widget = tester.widget<TodoWidget>(find.byType(TodoWidget));
      expect(widget.checked, isFalse);
    });
  });

  group('BlockRenderer — node with no delta', () {
    testWidgets('paragraph with null delta renders without error', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          BlockRenderer(
            node: BlockNode(id: 'b1', type: BlockTypes.paragraph),
            onEvent: (_) {},
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
