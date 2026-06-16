library;

import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';

import 'package:supanotes/features/notes/data/markdown_serializer.dart';

void main() {
  // ---------------------------------------------------------------------------
  // parseNoteToMarkdown
  // ---------------------------------------------------------------------------
  group('parseNoteToMarkdown', () {
    test('empty input returns a single empty paragraph', () {
      final doc = parseNoteToMarkdown('');

      expect(doc.nodeCount, 1);
      expect(doc.first, isA<ParagraphNode>());
      expect((doc.first as ParagraphNode).text.toPlainText(), '');
    });

    test('a plain line is a paragraph', () {
      final doc = parseNoteToMarkdown('hello world');

      expect(doc.nodeCount, 1);
      expect((doc.first as ParagraphNode).text.toPlainText(), 'hello world');
    });

    test('H1, H2, H3 are parsed with the matching block attribution', () {
      final doc = parseNoteToMarkdown('# Title\n## Sub\n### SubSub');

      expect(doc.nodeCount, 3);
      expect(_blockType(doc.getNodeAt(0)!), header1Attribution);
      expect(_blockType(doc.getNodeAt(1)!), header2Attribution);
      expect(_blockType(doc.getNodeAt(2)!), header3Attribution);
    });

    test('block quote is parsed with the quote attribution', () {
      final doc = parseNoteToMarkdown('> quoted');

      expect(doc.nodeCount, 1);
      expect(_blockType(doc.first), blockquoteAttribution);
      expect((doc.first as ParagraphNode).text.toPlainText(), 'quoted');
    });

    test('unordered list item is a ListItemNode', () {
      final doc = parseNoteToMarkdown('- item');

      expect(doc.nodeCount, 2);
      expect(doc.first, isA<ListItemNode>());
      expect((doc.first as ListItemNode).type, ListItemType.unordered);
    });

    test('ordered list item is a ListItemNode', () {
      final doc = parseNoteToMarkdown('1. first');

      expect(doc.nodeCount, 2);
      expect(doc.first, isA<ListItemNode>());
      expect((doc.first as ListItemNode).type, ListItemType.ordered);
    });

    test('open task is a TaskNode marked incomplete', () {
      final doc = parseNoteToMarkdown('- [ ] buy milk');

      expect(doc.first, isA<TaskNode>());
      expect((doc.first as TaskNode).isComplete, isFalse);
      expect((doc.first as TaskNode).text.toPlainText(), 'buy milk');
    });

    test('completed task is a TaskNode marked complete', () {
      final doc = parseNoteToMarkdown('- [x] pay rent');

      expect(doc.first, isA<TaskNode>());
      expect((doc.first as TaskNode).isComplete, isTrue);
    });

    test('task id marker is preserved across the parse step', () {
      final doc = parseNoteToMarkdown(
        '- [ ] call doctor <!-- task:abc-123 -->',
      );

      expect((doc.first as TaskNode).id, 'abc-123');
      expect((doc.first as TaskNode).text.toPlainText(), 'call doctor');
    });

    test('horizontal rule is parsed with preserved id and metadata', () {
      final doc = parseNoteToMarkdown('--- <!-- divider:hr-123|index:5 -->');
      expect(doc.first, isA<HorizontalRuleNode>());
      expect((doc.first as HorizontalRuleNode).id, 'hr-123');
      expect(
        (doc.first as HorizontalRuleNode).getMetadataValue('dividerIndex'),
        5,
      );
    });

    test('plain horizontal rule creates a HorizontalRuleNode', () {
      final doc = parseNoteToMarkdown('---');
      expect(doc.first, isA<HorizontalRuleNode>());
    });
  });

  // ---------------------------------------------------------------------------
  // inline formatting
  // ---------------------------------------------------------------------------
  group('inline formatting', () {
    test('**bold** is recognised as bold', () {
      final doc = parseNoteToMarkdown('this is **bold** text');

      final text = (doc.first as ParagraphNode).text;
      final spans = text.getAttributionSpansInRange(
        attributionFilter: (a) => a == boldAttribution,
        range: SpanRange(0, text.toPlainText().length),
      );
      expect(spans, isNotEmpty);
      expect(text.toPlainText(), 'this is bold text');
    });

    test('*italic* is recognised as italic', () {
      final doc = parseNoteToMarkdown('this is *italic* text');

      final text = (doc.first as ParagraphNode).text;
      final spans = text.getAttributionSpansInRange(
        attributionFilter: (a) => a == italicsAttribution,
        range: SpanRange(0, text.toPlainText().length),
      );
      expect(spans, isNotEmpty);
      expect(text.toPlainText(), 'this is italic text');
    });

    test('math expression 2*3 does not toggle italic', () {
      final doc = parseNoteToMarkdown('2*3=6');

      final text = (doc.first as ParagraphNode).text;
      final spans = text.getAttributionSpansInRange(
        attributionFilter: (a) => a == italicsAttribution,
        range: SpanRange(0, text.toPlainText().length),
      );
      expect(spans, isEmpty);
      expect(text.toPlainText(), '2*3=6');
    });

    test('escaped asterisk is treated as a literal', () {
      final doc = parseNoteToMarkdown(r'a \* b');

      final text = (doc.first as ParagraphNode).text;
      expect(text.toPlainText(), 'a * b');
      final spans = text.getAttributionSpansInRange(
        attributionFilter: (a) => a == italicsAttribution,
        range: SpanRange(0, text.toPlainText().length),
      );
      expect(spans, isEmpty);
    });

    test('~strikethrough~ is recognised as strikethrough', () {
      final doc = parseNoteToMarkdown('this is ~strikethrough~ text');

      final text = (doc.first as ParagraphNode).text;
      final spans = text.getAttributionSpansInRange(
        attributionFilter: (a) => a == strikethroughAttribution,
        range: SpanRange(0, text.toPlainText().length),
      );
      expect(spans, isNotEmpty);
      expect(text.toPlainText(), 'this is strikethrough text');
    });

    test('serializer outputs ~strikethrough~ syntax', () {
      final text = AttributedText(
        'hello world',
        AttributedSpans(
          attributions: [
            const SpanMarker(
              attribution: strikethroughAttribution,
              offset: 0,
              markerType: SpanMarkerType.start,
            ),
            const SpanMarker(
              attribution: strikethroughAttribution,
              offset: 4,
              markerType: SpanMarkerType.end,
            ),
          ],
        ),
      );
      final doc = MutableDocument(
        nodes: [ParagraphNode(id: Editor.createNodeId(), text: text)],
      );

      final out = serializeNoteToMarkdown(doc);
      expect(out, '~hello~ world');
    });
  });

  // ---------------------------------------------------------------------------
  // serializeNoteToMarkdown
  // ---------------------------------------------------------------------------
  group('serializeNoteToMarkdown', () {
    test('round-trips a single paragraph', () {
      final doc = parseNoteToMarkdown('a simple note');
      expect(serializeNoteToMarkdown(doc), 'a simple note');
    });

    test('round-trips a heading', () {
      final doc = parseNoteToMarkdown('# Big Title');
      expect(serializeNoteToMarkdown(doc), '# Big Title');
    });

    test('round-trips a task and keeps the id marker', () {
      const id = 'task-xyz';
      const original = '- [ ] write tests <!-- task:$id -->';
      final doc = parseNoteToMarkdown(original);
      expect(serializeNoteToMarkdown(doc), original);
    });

    test('round-trips multiple blocks with blank lines', () {
      const original = '# Title\n\nA paragraph after a blank line.';
      final doc = parseNoteToMarkdown(original);
      final out = serializeNoteToMarkdown(doc);
      expect(out, original);
    });

    test('multiple paragraphs separated by blank lines are preserved', () {
      const original = 'first paragraph\n\nsecond paragraph\n\nthird';
      final doc = parseNoteToMarkdown(original);
      final out = serializeNoteToMarkdown(doc);
      expect(out, original);
    });

    test('strikethrough round-trips', () {
      const original = 'text with ~strikethrough~ inside';
      final doc = parseNoteToMarkdown(original);
      expect(serializeNoteToMarkdown(doc), original);
    });

    test('bold round-trips', () {
      const original = 'text with **bold** inside';
      final doc = parseNoteToMarkdown(original);
      expect(serializeNoteToMarkdown(doc), original);
    });

    test('italic round-trips', () {
      const original = 'text with *italic* inside';
      final doc = parseNoteToMarkdown(original);
      expect(serializeNoteToMarkdown(doc), original);
    });

    test('bold and italic on separate spans round-trip', () {
      const original = '**bold** and *italic* text';
      final doc = parseNoteToMarkdown(original);
      expect(serializeNoteToMarkdown(doc), original);
    });

    test('bold inside strikethrough round-trips', () {
      const original = '~**bold-strike**~';
      final doc = parseNoteToMarkdown(original);
      final out = serializeNoteToMarkdown(doc);

      expect((doc.first as ParagraphNode).text.toPlainText(), 'bold-strike');

      final text = (doc.first as ParagraphNode).text;
      final boldSpans = text.getAttributionSpansInRange(
        attributionFilter: (a) => a == boldAttribution,
        range: SpanRange(0, text.toPlainText().length),
      );
      final strikeSpans = text.getAttributionSpansInRange(
        attributionFilter: (a) => a == strikethroughAttribution,
        range: SpanRange(0, text.toPlainText().length),
      );
      expect(
        boldSpans,
        isNotEmpty,
        reason: 'bold attribution must survive parse',
      );
      expect(
        strikeSpans,
        isNotEmpty,
        reason: 'strikethrough attribution must survive parse',
      );
      expect(out, contains('**'), reason: 'bold marker must appear in output');
      expect(
        out,
        contains('~'),
        reason: 'strikethrough marker must appear in output',
      );
    });

    test('horizontal rule round-trips and keeps the id marker and index', () {
      const original = '--- <!-- divider:hr-123|index:5 -->';
      final doc = parseNoteToMarkdown(original);
      expect(serializeNoteToMarkdown(doc), original);
    });

    test('link round-trips', () {
      const original = 'a [link](https://example.com) here';
      final doc = parseNoteToMarkdown(original);
      expect(serializeNoteToMarkdown(doc), original);
    });

    test(
      'preserves headings, tasks, and following bullet lists after save and local refresh',
      () {
        const original = '''# Projeto
## Plano
- [ ] Escrever relatório <!-- task:task-1 -->
- Revisar escopo
- Levantar riscos
- Definir próximos passos
- [ ] Atualizar documentação <!-- task:task-2 -->
- Confirmar revisão
- Publicar changelog
- Avisar usuários''';

        const expectedSavedMarkdown = '''# Projeto

## Plano

- [ ] Escrever relatório <!-- task:task-1 -->
  * Revisar escopo
  * Levantar riscos
  * Definir próximos passos

- [ ] Atualizar documentação <!-- task:task-2 -->
  * Confirmar revisão
  * Publicar changelog
  * Avisar usuários''';

        final savedMarkdown = serializeNoteToMarkdown(
          parseNoteToMarkdown(original),
        );
        final reloadedFromServerMarkdown = serializeNoteToMarkdown(
          parseNoteToMarkdown(savedMarkdown),
        );
        final refreshedLocalMarkdown = serializeNoteToMarkdown(
          parseNoteToMarkdown(reloadedFromServerMarkdown),
        );

        expect(savedMarkdown, expectedSavedMarkdown);
        expect(reloadedFromServerMarkdown, savedMarkdown);
        expect(refreshedLocalMarkdown, savedMarkdown);
      },
    );
  });
}

Attribution? _blockType(DocumentNode node) {
  if (node is! ParagraphNode) return null;
  return node.getMetadataValue('blockType') as Attribution?;
}
