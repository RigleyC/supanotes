import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:block_editor/block_editor.dart';

void main() {
  group('VariableOp', () {
    test('stores variableName', () {
      const op = VariableOp('userName');
      expect(op.variableName, 'userName');
    });

    test('toJson produces correct map', () {
      const op = VariableOp('title');
      expect(op.toJson(), {'type': 'variable', 'variableName': 'title'});
    });

    test('fromJson round-trips correctly', () {
      const op = VariableOp('count');
      final restored = DeltaOp.fromJson(op.toJson());
      expect(restored, isA<VariableOp>());
      expect((restored as VariableOp).variableName, 'count');
    });

    test('equality holds for same variableName', () {
      expect(const VariableOp('x'), const VariableOp('x'));
    });

    test('equality fails for different variableName', () {
      expect(const VariableOp('x'), isNot(const VariableOp('y')));
    });

    test('hashCode is consistent', () {
      expect(
        const VariableOp('name').hashCode,
        const VariableOp('name').hashCode,
      );
    });

    test('toString includes variableName', () {
      expect(const VariableOp('foo').toString(), contains('foo'));
    });
  });

  group('TagOp', () {
    test('stores tag', () {
      const op = TagOp('flutter');
      expect(op.tag, 'flutter');
    });

    test('toJson produces correct map', () {
      const op = TagOp('dart');
      expect(op.toJson(), {'type': 'tag', 'tag': 'dart'});
    });

    test('fromJson round-trips correctly', () {
      const op = TagOp('mobile');
      final restored = DeltaOp.fromJson(op.toJson());
      expect(restored, isA<TagOp>());
      expect((restored as TagOp).tag, 'mobile');
    });

    test('equality holds for same tag', () {
      expect(const TagOp('a'), const TagOp('a'));
    });

    test('equality fails for different tag', () {
      expect(const TagOp('a'), isNot(const TagOp('b')));
    });

    test('hashCode is consistent', () {
      expect(const TagOp('x').hashCode, const TagOp('x').hashCode);
    });

    test('toString includes tag', () {
      expect(const TagOp('bar').toString(), contains('bar'));
    });
  });

  group('BlockController.tags', () {
    test('returns empty set when no tags present', () {
      final controller = BlockController(document: const BlockDocument([]));
      controller.append(
        BlockNode(
          type: BlockTypes.paragraph,
          delta: TextDelta.fromPlainText('no tags here'),
        ),
      );
      expect(controller.tags, isEmpty);
      controller.dispose();
    });

    test('returns tags from a single block', () {
      final controller = BlockController(document: const BlockDocument([]));
      controller.append(
        BlockNode(
          type: BlockTypes.paragraph,
          delta: TextDelta([const TextOp('hello '), const TagOp('flutter')]),
        ),
      );
      expect(controller.tags, {'flutter'});
      controller.dispose();
    });

    test('returns unique tags across multiple blocks', () {
      final controller = BlockController(document: const BlockDocument([]));
      controller.append(
        BlockNode(
          type: BlockTypes.paragraph,
          delta: TextDelta([const TagOp('dart'), const TagOp('flutter')]),
        ),
      );
      controller.append(
        BlockNode(
          type: BlockTypes.paragraph,
          delta: TextDelta([const TagOp('dart'), const TagOp('mobile')]),
        ),
      );
      expect(controller.tags, {'dart', 'flutter', 'mobile'});
      controller.dispose();
    });

    test('updates when blocks are mutated', () {
      final controller = BlockController(document: const BlockDocument([]));
      final node = BlockNode(
        type: BlockTypes.paragraph,
        delta: TextDelta([const TagOp('initial')]),
      );
      controller.append(node);
      expect(controller.tags, {'initial'});
      controller.updateDelta(node.id, TextDelta([const TagOp('updated')]));
      expect(controller.tags, {'updated'});
      controller.dispose();
    });
  });

  group('RichTextRenderer — VariableOp', () {
    testWidgets('resolved variable renders as text', (tester) async {
      final delta = TextDelta([const VariableOp('name')]);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: BlockEditorScope(
            variables: const {'name': 'Alice'},
            child: RichTextRenderer(delta: delta, blockId: 'b1'),
          ),
        ),
      );
      expect(find.text('Alice', findRichText: true), findsOneWidget);
    });

    testWidgets('unresolved variable renders as placeholder', (tester) async {
      final delta = TextDelta([const VariableOp('missing')]);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: BlockEditorScope(
            child: RichTextRenderer(delta: delta, blockId: 'b1'),
          ),
        ),
      );
      expect(find.text('{{missing}}', findRichText: true), findsOneWidget);
    });

    testWidgets('variable span uses purple color', (tester) async {
      final delta = TextDelta([const VariableOp('x')]);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: BlockEditorScope(
            variables: const {'x': 'val'},
            child: RichTextRenderer(delta: delta, blockId: 'b1'),
          ),
        ),
      );
      final text = tester.widget<Text>(find.byType(Text));
      final root = text.textSpan! as TextSpan;
      final span = root.children!.first as TextSpan;
      expect(span.style!.color, const Color(0xFF8B5CF6));
    });
  });

  group('RichTextRenderer — TagOp', () {
    testWidgets('tag renders with # prefix', (tester) async {
      final delta = TextDelta([const TagOp('flutter')]);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: BlockEditorScope(
            child: RichTextRenderer(delta: delta, blockId: 'b1'),
          ),
        ),
      );
      expect(find.text('#flutter', findRichText: true), findsOneWidget);
    });

    testWidgets('tag span uses blue color', (tester) async {
      final delta = TextDelta([const TagOp('dart')]);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: BlockEditorScope(
            child: RichTextRenderer(delta: delta, blockId: 'b1'),
          ),
        ),
      );
      final text = tester.widget<Text>(find.byType(Text));
      final root = text.textSpan! as TextSpan;
      final span = root.children!.first as TextSpan;
      expect(span.style!.color, const Color(0xFF0EA5E9));
    });
  });

  group('BlockEditorScope', () {
    testWidgets('maybeOf returns null when no scope in tree', (tester) async {
      late BlockEditorScope? found;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
            builder: (context) {
              found = BlockEditorScope.maybeOf(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(found, isNull);
    });

    testWidgets('maybeOf returns scope when present', (tester) async {
      late BlockEditorScope? found;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: BlockEditorScope(
            variables: const {'key': 'value'},
            child: Builder(
              builder: (context) {
                found = BlockEditorScope.maybeOf(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      expect(found, isNotNull);
      expect(found!.variables['key'], 'value');
    });

    testWidgets('readOnly defaults to false', (tester) async {
      late BlockEditorScope? found;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: BlockEditorScope(
            child: Builder(
              builder: (context) {
                found = BlockEditorScope.maybeOf(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      expect(found!.readOnly, isFalse);
    });

    testWidgets('readOnly is accessible from context', (tester) async {
      late BlockEditorScope? found;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: BlockEditorScope(
            readOnly: true,
            child: Builder(
              builder: (context) {
                found = BlockEditorScope.maybeOf(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      expect(found!.readOnly, isTrue);
    });
  });
}
