import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:block_editor/block_editor.dart';

Widget wrap(Widget child) {
  return Directionality(textDirection: TextDirection.ltr, child: child);
}

BlockNode codeNode({String code = 'print("hello")', String language = 'dart'}) {
  return BlockNode(
    type: BlockTypes.code,
    attributes: {'code': code, 'language': language},
  );
}

void main() {
  group('CodeBlock — plugin contract', () {
    test('blockType is code', () {
      expect(CodeBlock().blockType, BlockTypes.code);
    });

    test('serialize round-trips via toJson', () {
      final node = codeNode();
      final json = CodeBlock().serialize(node);
      expect(json['type'], BlockTypes.code);
    });

    test('deserialize produces correct type', () {
      final node = codeNode();
      final json = CodeBlock().serialize(node);
      final restored = CodeBlock().deserialize(json);
      expect(restored.type, BlockTypes.code);
    });

    test('slashCommandItem label is Code', () {
      expect(CodeBlock().slashCommandItem().label, 'Code');
    });

    test('slashCommandGroup is Basic', () {
      expect(CodeBlock().slashCommandGroup(), 'Basic');
    });
  });

  group('CodeBlock — rendering', () {
    testWidgets('renders code content', (tester) async {
      await tester.pumpWidget(
        wrap(
          BlockEditorScope(
            child: Builder(
              builder: (context) {
                return CodeBlock().build(
                  codeNode(code: 'var x = 1;'),
                  EditorSelection.none,
                  (_) {},
                );
              },
            ),
          ),
        ),
      );
      expect(find.text('var x = 1;'), findsOneWidget);
    });

    testWidgets('renders language label when showLanguageSelector is true', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          BlockEditorScope(
            child: Builder(
              builder: (context) {
                return CodeBlock().build(
                  codeNode(language: 'python'),
                  EditorSelection.none,
                  (_) {},
                );
              },
            ),
          ),
        ),
      );
      expect(find.text('python'), findsOneWidget);
    });

    testWidgets('hides language label when showLanguageSelector is false', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          BlockEditorScope(
            codeConfig: const CodeBlockConfig(showLanguageSelector: false),
            child: Builder(
              builder: (context) {
                return CodeBlock().build(
                  codeNode(language: 'dart'),
                  EditorSelection.none,
                  (_) {},
                );
              },
            ),
          ),
        ),
      );
      expect(find.text('dart'), findsNothing);
    });

    testWidgets('renders line numbers when showLineNumbers is true', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          BlockEditorScope(
            child: Builder(
              builder: (context) {
                return CodeBlock().build(
                  codeNode(code: 'line1\nline2\nline3'),
                  EditorSelection.none,
                  (_) {},
                );
              },
            ),
          ),
        ),
      );
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('hides line numbers when showLineNumbers is false', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          BlockEditorScope(
            codeConfig: const CodeBlockConfig(showLineNumbers: false),
            child: Builder(
              builder: (context) {
                return CodeBlock().build(
                  codeNode(code: 'line1\nline2'),
                  EditorSelection.none,
                  (_) {},
                );
              },
            ),
          ),
        ),
      );
      expect(find.text('1'), findsNothing);
      expect(find.text('2'), findsNothing);
    });

    testWidgets('emits code_language_change_requested on language label tap', (
      tester,
    ) async {
      BlockEvent? received;
      await tester.pumpWidget(
        wrap(
          BlockEditorScope(
            child: Builder(
              builder: (context) {
                return CodeBlock().build(
                  codeNode(language: 'dart'),
                  EditorSelection.none,
                  (e) => received = e,
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('dart'));
      expect(received, isA<CustomBlockEvent>());
      final event = received as CustomBlockEvent;
      expect(event.eventType, 'code_language_change_requested');
      expect(event.payload, 'dart');
    });

    testWidgets('renders without error on empty code', (tester) async {
      await tester.pumpWidget(
        wrap(
          BlockEditorScope(
            child: Builder(
              builder: (context) {
                return CodeBlock().build(
                  codeNode(code: ''),
                  EditorSelection.none,
                  (_) {},
                );
              },
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders default language when absent', (tester) async {
      await tester.pumpWidget(
        wrap(
          BlockEditorScope(
            child: Builder(
              builder: (context) {
                return CodeBlock().build(
                  BlockNode(type: BlockTypes.code),
                  EditorSelection.none,
                  (_) {},
                );
              },
            ),
          ),
        ),
      );
      expect(find.text('plaintext'), findsOneWidget);
    });
  });
}
