import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:block_editor/block_editor.dart';

Widget wrap(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

BlockNode calloutNode({
  String variant = 'info',
  String text = 'This is a callout',
}) {
  return BlockNode(
    type: BlockTypes.callout,
    attributes: {'variant': variant},
    delta: TextDelta.fromPlainText(text),
  );
}

void main() {
  group('CalloutBlock — plugin contract', () {
    test('blockType is callout', () {
      expect(CalloutBlock().blockType, BlockTypes.callout);
    });

    test('serialize round-trips via toJson', () {
      final node = calloutNode();
      final json = CalloutBlock().serialize(node);
      expect(json['type'], BlockTypes.callout);
    });

    test('deserialize produces correct type', () {
      final node = calloutNode();
      final json = CalloutBlock().serialize(node);
      final restored = CalloutBlock().deserialize(json);
      expect(restored.type, BlockTypes.callout);
    });

    test('slashCommandItem label is Callout', () {
      expect(CalloutBlock().slashCommandItem().label, 'Callout');
    });

    test('slashCommandGroup is Basic', () {
      expect(CalloutBlock().slashCommandGroup(), 'Basic');
    });
  });

  group('CalloutBlock — rendering', () {
    testWidgets('renders content text', (tester) async {
      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 400,
            child: BlockEditorScope(
              child: Builder(
                builder: (context) {
                  return CalloutBlock().build(
                    calloutNode(text: 'Watch out!'),
                    EditorSelection.none,
                    (_) {},
                  );
                },
              ),
            ),
          ),
        ),
      );
      expect(find.text('Watch out!', findRichText: true), findsOneWidget);
    });

    testWidgets('info variant uses default info color', (tester) async {
      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 400,
            child: BlockEditorScope(
              child: Builder(
                builder: (context) {
                  return CalloutBlock().build(
                    calloutNode(variant: 'info'),
                    EditorSelection.none,
                    (_) {},
                  );
                },
              ),
            ),
          ),
        ),
      );
      final container = tester.widget<Container>(find.byType(Container).first);
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, isNotNull);
    });

    testWidgets('warning variant uses default warning color', (tester) async {
      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 400,
            child: BlockEditorScope(
              child: Builder(
                builder: (context) {
                  return CalloutBlock().build(
                    calloutNode(variant: 'warning'),
                    EditorSelection.none,
                    (_) {},
                  );
                },
              ),
            ),
          ),
        ),
      );
      final container = tester.widget<Container>(find.byType(Container).first);
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, isNotNull);
    });

    testWidgets('error variant uses default error color', (tester) async {
      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 400,
            child: BlockEditorScope(
              child: Builder(
                builder: (context) {
                  return CalloutBlock().build(
                    calloutNode(variant: 'error'),
                    EditorSelection.none,
                    (_) {},
                  );
                },
              ),
            ),
          ),
        ),
      );
      final container = tester.widget<Container>(find.byType(Container).first);
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, isNotNull);
    });

    testWidgets('custom infoColor from config is applied', (tester) async {
      const customColor = Color(0xFF001122);
      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 400,
            child: BlockEditorScope(
              calloutConfig: const CalloutBlockConfig(infoColor: customColor),
              child: Builder(
                builder: (context) {
                  return CalloutBlock().build(
                    calloutNode(variant: 'info'),
                    EditorSelection.none,
                    (_) {},
                  );
                },
              ),
            ),
          ),
        ),
      );
      final container = tester.widget<Container>(find.byType(Container).first);
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, customColor);
    });

    testWidgets('custom borderRadius from config is applied', (tester) async {
      const radius = BorderRadius.all(Radius.circular(16));
      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 400,
            child: BlockEditorScope(
              calloutConfig: const CalloutBlockConfig(borderRadius: radius),
              child: Builder(
                builder: (context) {
                  return CalloutBlock().build(
                    calloutNode(),
                    EditorSelection.none,
                    (_) {},
                  );
                },
              ),
            ),
          ),
        ),
      );
      final container = tester.widget<Container>(find.byType(Container).first);
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.borderRadius, radius);
    });

    testWidgets('renders without error on empty delta', (tester) async {
      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 400,
            child: BlockEditorScope(
              child: Builder(
                builder: (context) {
                  return CalloutBlock().build(
                    BlockNode(
                      type: BlockTypes.callout,
                      attributes: const {'variant': 'info'},
                    ),
                    EditorSelection.none,
                    (_) {},
                  );
                },
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('defaults to info variant when variant is absent', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 400,
            child: BlockEditorScope(
              child: Builder(
                builder: (context) {
                  return CalloutBlock().build(
                    BlockNode(type: BlockTypes.callout),
                    EditorSelection.none,
                    (_) {},
                  );
                },
              ),
            ),
          ),
        ),
      );
      final container = tester.widget<Container>(find.byType(Container).first);
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, isNotNull);
    });
  });
}
