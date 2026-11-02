import 'package:block_editor/block_editor.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget wrap(Widget child) {
  return Directionality(textDirection: TextDirection.ltr, child: child);
}

TextSpan firstSpanFrom(WidgetTester tester) {
  final text = tester.widget<Text>(find.byType(Text));
  final root = text.textSpan! as TextSpan;
  return root.children!.first as TextSpan;
}

void main() {
  group('RichTextRenderer — plain text', () {
    testWidgets('renders plain text content', (tester) async {
      await tester.pumpWidget(
        wrap(
          RichTextRenderer(
            delta: TextDelta.fromPlainText('hello world'),
            blockId: 'b1',
          ),
        ),
      );
      expect(find.text('hello world', findRichText: true), findsOneWidget);
    });

    testWidgets('renders empty delta without error', (tester) async {
      await tester.pumpWidget(
        wrap(
          RichTextRenderer(delta: TextDelta.fromPlainText(''), blockId: 'b1'),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('RichTextRenderer — inline attributes', () {
    testWidgets('bold op produces bold TextSpan', (tester) async {
      final delta = TextDelta.fromPlainText(
        'bold text',
      ).applyAttributes(0, 9, const InlineAttributes(bold: true));
      await tester.pumpWidget(
        wrap(RichTextRenderer(delta: delta, blockId: 'b1')),
      );
      expect(firstSpanFrom(tester).style!.fontWeight, FontWeight.bold);
    });

    testWidgets('italic op produces italic TextSpan', (tester) async {
      final delta = TextDelta.fromPlainText(
        'italic',
      ).applyAttributes(0, 6, const InlineAttributes(italic: true));
      await tester.pumpWidget(
        wrap(RichTextRenderer(delta: delta, blockId: 'b1')),
      );
      expect(firstSpanFrom(tester).style!.fontStyle, FontStyle.italic);
    });

    testWidgets('underline op produces underline decoration', (tester) async {
      final delta = TextDelta.fromPlainText(
        'underlined',
      ).applyAttributes(0, 10, const InlineAttributes(underline: true));
      await tester.pumpWidget(
        wrap(RichTextRenderer(delta: delta, blockId: 'b1')),
      );
      expect(
        firstSpanFrom(
          tester,
        ).style!.decoration!.contains(TextDecoration.underline),
        isTrue,
      );
    });

    testWidgets('strikethrough op produces lineThrough decoration', (
      tester,
    ) async {
      final delta = TextDelta.fromPlainText(
        'struck',
      ).applyAttributes(0, 6, const InlineAttributes(strikethrough: true));
      await tester.pumpWidget(
        wrap(RichTextRenderer(delta: delta, blockId: 'b1')),
      );
      expect(
        firstSpanFrom(
          tester,
        ).style!.decoration!.contains(TextDecoration.lineThrough),
        isTrue,
      );
    });

    testWidgets('inline code op uses monospace font and code background', (
      tester,
    ) async {
      final delta = TextDelta.fromPlainText(
        'code',
      ).applyAttributes(0, 4, const InlineAttributes(inlineCode: true));
      await tester.pumpWidget(
        wrap(RichTextRenderer(delta: delta, blockId: 'b1')),
      );
      final span = firstSpanFrom(tester);
      expect(span.style!.fontFamily, 'monospace');
      expect(span.style!.backgroundColor, const Color(0xFFEEEEEE));
    });

    testWidgets('link op uses link color', (tester) async {
      final delta = TextDelta.fromPlainText('click').applyAttributes(
        0,
        5,
        const InlineAttributes(link: 'https://example.com'),
      );
      await tester.pumpWidget(
        wrap(RichTextRenderer(delta: delta, blockId: 'b1')),
      );
      expect(firstSpanFrom(tester).style!.color, const Color(0xFF0070F3));
    });

    testWidgets('underline and strikethrough combine correctly', (
      tester,
    ) async {
      final delta = TextDelta.fromPlainText('both').applyAttributes(
        0,
        4,
        const InlineAttributes(underline: true, strikethrough: true),
      );
      await tester.pumpWidget(
        wrap(RichTextRenderer(delta: delta, blockId: 'b1')),
      );
      final span = firstSpanFrom(tester);
      expect(
        span.style!.decoration!.contains(TextDecoration.underline),
        isTrue,
      );
      expect(
        span.style!.decoration!.contains(TextDecoration.lineThrough),
        isTrue,
      );
    });

    testWidgets('text color is applied from hex string', (tester) async {
      final delta = TextDelta.fromPlainText(
        'colored',
      ).applyAttributes(0, 7, const InlineAttributes(color: '#FF0000'));
      await tester.pumpWidget(
        wrap(RichTextRenderer(delta: delta, blockId: 'b1')),
      );
      expect(firstSpanFrom(tester).style!.color, const Color(0xFFFF0000));
    });
  });

  group('RichTextRenderer — selection highlight', () {
    testWidgets('no highlight for NoSelection', (tester) async {
      final delta = TextDelta.fromPlainText('hello');
      await tester.pumpWidget(
        wrap(
          RichTextRenderer(
            delta: delta,
            blockId: 'b1',
            selection: EditorSelection.none,
          ),
        ),
      );
      final span = firstSpanFrom(tester);
      expect(span.style?.backgroundColor, isNot(const Color(0x443399FF)));
    });

    testWidgets('no highlight for CollapsedSelection', (tester) async {
      final delta = TextDelta.fromPlainText('hello');
      await tester.pumpWidget(
        wrap(
          RichTextRenderer(
            delta: delta,
            blockId: 'b1',
            selection: const CollapsedSelection(
              SelectionPoint(blockId: 'b1', offset: 2),
            ),
          ),
        ),
      );
      final span = firstSpanFrom(tester);
      expect(span.style?.backgroundColor, isNot(const Color(0x443399FF)));
    });

    testWidgets('highlight applied to op within selection range', (
      tester,
    ) async {
      final delta = TextDelta.fromPlainText('hello');
      await tester.pumpWidget(
        wrap(
          RichTextRenderer(
            delta: delta,
            blockId: 'b1',
            selection: const ExpandedSelection(
              anchor: SelectionPoint(blockId: 'b1', offset: 0),
              focus: SelectionPoint(blockId: 'b1', offset: 5),
            ),
          ),
        ),
      );
      final span = firstSpanFrom(tester);
      expect(span.style!.backgroundColor, const Color(0x443399FF));
    });

    testWidgets('op outside selection range has no highlight', (tester) async {
      final delta = TextDelta.fromPlainText('hello world');
      await tester.pumpWidget(
        wrap(
          RichTextRenderer(
            delta: delta,
            blockId: 'b1',
            selection: const ExpandedSelection(
              anchor: SelectionPoint(blockId: 'b1', offset: 6),
              focus: SelectionPoint(blockId: 'b1', offset: 11),
            ),
          ),
        ),
      );
      final span = firstSpanFrom(tester);
      expect(span.style?.backgroundColor, isNot(const Color(0x443399FF)));
    });
  });

  group('RichTextRenderer — base style', () {
    testWidgets('baseStyle is applied to root TextSpan', (tester) async {
      const base = TextStyle(fontSize: 24, fontWeight: FontWeight.w700);
      await tester.pumpWidget(
        wrap(
          RichTextRenderer(
            delta: TextDelta.fromPlainText('heading'),
            blockId: 'b1',
            baseStyle: base,
          ),
        ),
      );
      final text = tester.widget<Text>(find.byType(Text));
      expect(text.textSpan!.style!.fontSize, 24);
      expect(text.textSpan!.style!.fontWeight, FontWeight.w700);
    });
  });

  group('RichTextRenderer — text alignment', () {
    testWidgets('textAlign is forwarded to Text.rich', (tester) async {
      await tester.pumpWidget(
        wrap(
          RichTextRenderer(
            delta: TextDelta.fromPlainText('centered'),
            blockId: 'b1',
            textAlign: TextAlign.center,
          ),
        ),
      );
      final richText = tester.widget<RichText>(find.byType(RichText));
      expect(richText.textAlign, TextAlign.center);
    });
  });

  group('RichTextRenderer — composing range', () {
    testWidgets('null composingRange renders without error', (tester) async {
      await tester.pumpWidget(
        wrap(
          RichTextRenderer(
            delta: TextDelta.fromPlainText('hello'),
            blockId: 'b1',
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('composingRange applies underline to composing span', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          RichTextRenderer(
            delta: TextDelta.fromPlainText('hello'),
            blockId: 'b1',
            composingRange: const TextRange(start: 1, end: 3),
          ),
        ),
      );
      final text = tester.widget<Text>(find.byType(Text));
      final root = text.textSpan! as TextSpan;
      final composingSpan = root.children!.whereType<TextSpan>().firstWhere(
        (s) => s.text == 'el',
      );
      expect(
        composingSpan.style!.decoration!.contains(TextDecoration.underline),
        isTrue,
      );
    });

    testWidgets(
      'characters outside composingRange have no composing underline',
      (tester) async {
        await tester.pumpWidget(
          wrap(
            RichTextRenderer(
              delta: TextDelta.fromPlainText('hello'),
              blockId: 'b1',
              composingRange: const TextRange(start: 1, end: 3),
            ),
          ),
        );
        final text = tester.widget<Text>(find.byType(Text));
        final root = text.textSpan! as TextSpan;
        final beforeSpan = root.children!.whereType<TextSpan>().firstWhere(
          (s) => s.text == 'h',
        );
        expect(beforeSpan.style?.decoration, isNull);
      },
    );

    testWidgets('empty composingRange renders without underline', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          RichTextRenderer(
            delta: TextDelta.fromPlainText('hello'),
            blockId: 'b1',
            composingRange: TextRange.empty,
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      final span = firstSpanFrom(tester);
      expect(span.style?.decoration, isNull);
    });

    testWidgets('composingRange combines with existing bold formatting', (
      tester,
    ) async {
      final delta = TextDelta.fromPlainText(
        'hello',
      ).applyAttributes(0, 5, const InlineAttributes(bold: true));
      await tester.pumpWidget(
        wrap(
          RichTextRenderer(
            delta: delta,
            blockId: 'b1',
            composingRange: const TextRange(start: 0, end: 3),
          ),
        ),
      );
      final text = tester.widget<Text>(find.byType(Text));
      final root = text.textSpan! as TextSpan;
      final composingSpan = root.children!.whereType<TextSpan>().firstWhere(
        (s) => s.text == 'hel',
      );
      expect(composingSpan.style!.fontWeight, FontWeight.bold);
      expect(
        composingSpan.style!.decoration!.contains(TextDecoration.underline),
        isTrue,
      );
    });
  });
}
