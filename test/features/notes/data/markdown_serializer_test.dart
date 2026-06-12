/// Unit tests for the markdown ↔ super_editor bridge.
///
/// The serializer is the only thing that knows how to translate the rich
/// document the user edits back into the markdown blob stored in
/// `notes.content`. Every behaviour the editor and inbox depend on has
/// to be covered here so that regressions in the parser are caught
/// before they corrupt a note.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart'
    hide serializeDocumentToMarkdown;

import 'package:supanotes/features/notes/data/markdown_serializer.dart';

void main() {
  group('parseMarkdownToDocument', () {
    test('empty input returns a single empty paragraph', () {
      final doc = parseMarkdownToDocument('');

      expect(doc.nodeCount, 1);
      expect(doc.first, isA<ParagraphNode>());
      expect((doc.first as ParagraphNode).text.toPlainText(), '');
    });

    test('a plain line is a paragraph', () {
      final doc = parseMarkdownToDocument('hello world');

      expect(doc.nodeCount, 1);
      expect((doc.first as ParagraphNode).text.toPlainText(), 'hello world');
    });

    test('H1, H2, H3 are parsed with the matching block attribution', () {
      final doc = parseMarkdownToDocument('# Title\n## Sub\n### SubSub');

      expect(doc.nodeCount, 3);
      expect(_blockType(doc.getNodeAt(0)!), header1Attribution);
      expect(_blockType(doc.getNodeAt(1)!), header2Attribution);
      expect(_blockType(doc.getNodeAt(2)!), header3Attribution);
    });

    test('block quote is parsed with the quote attribution', () {
      final doc = parseMarkdownToDocument('> quoted');

      expect(doc.nodeCount, 1);
      expect(_blockType(doc.first), blockquoteAttribution);
      expect((doc.first as ParagraphNode).text.toPlainText(), 'quoted');
    });

    test('unordered list item is a ListItemNode', () {
      final doc = parseMarkdownToDocument('- item');

      expect(doc.nodeCount, 1);
      expect(doc.first, isA<ListItemNode>());
      expect((doc.first as ListItemNode).type, ListItemType.unordered);
    });

    test('ordered list item is a ListItemNode', () {
      final doc = parseMarkdownToDocument('1. first');

      expect(doc.nodeCount, 1);
      expect(doc.first, isA<ListItemNode>());
      expect((doc.first as ListItemNode).type, ListItemType.ordered);
    });

    test('open task is a TaskNode marked incomplete', () {
      final doc = parseMarkdownToDocument('- [ ] buy milk');

      expect(doc.first, isA<TaskNode>());
      expect((doc.first as TaskNode).isComplete, isFalse);
      expect(
        (doc.first as TaskNode).text.toPlainText(),
        'buy milk',
      );
    });

    test('completed task is a TaskNode marked complete', () {
      final doc = parseMarkdownToDocument('- [x] pay rent');

      expect(doc.first, isA<TaskNode>());
      expect((doc.first as TaskNode).isComplete, isTrue);
    });

    test('task id marker is preserved across the parse step', () {
      final doc = parseMarkdownToDocument(
        '- [ ] call doctor <!-- task:abc-123 -->',
      );

      expect((doc.first as TaskNode).id, 'abc-123');
      expect(
        (doc.first as TaskNode).text.toPlainText(),
        'call doctor',
      );
    });
  });

  group('inline formatting', () {
    test('**bold** is recognised as bold', () {
      final doc = parseMarkdownToDocument('this is **bold** text');

      final text = (doc.first as ParagraphNode).text;
      final spans = text.getAttributionSpansInRange(
        attributionFilter: (a) => a == boldAttribution,
        range: SpanRange(0, text.toPlainText().length),
      );
      expect(spans, isNotEmpty);
      expect(text.toPlainText(), 'this is bold text');
    });

    test('*italic* is recognised as italic', () {
      final doc = parseMarkdownToDocument('this is *italic* text');

      final text = (doc.first as ParagraphNode).text;
      final spans = text.getAttributionSpansInRange(
        attributionFilter: (a) => a == italicsAttribution,
        range: SpanRange(0, text.toPlainText().length),
      );
      expect(spans, isNotEmpty);
      expect(text.toPlainText(), 'this is italic text');
    });

    test('math expression 2*3 does not toggle italic', () {
      final doc = parseMarkdownToDocument('2*3=6');

      final text = (doc.first as ParagraphNode).text;
      final spans = text.getAttributionSpansInRange(
        attributionFilter: (a) => a == italicsAttribution,
        range: SpanRange(0, text.toPlainText().length),
      );
      expect(spans, isEmpty);
      expect(text.toPlainText(), '2*3=6');
    });

    test('escaped asterisk is treated as a literal', () {
      final doc = parseMarkdownToDocument(r'a \* b');

      final text = (doc.first as ParagraphNode).text;
      expect(text.toPlainText(), 'a * b');
      final spans = text.getAttributionSpansInRange(
        attributionFilter: (a) => a == italicsAttribution,
        range: SpanRange(0, text.toPlainText().length),
      );
      expect(spans, isEmpty);
    });

    test('~strikethrough~ is recognised as strikethrough', () {
      final doc = parseMarkdownToDocument('this is ~strikethrough~ text');

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
              offset: 5,
              markerType: SpanMarkerType.end,
            ),
          ],
        ),
      );
      final doc = MutableDocument(nodes: [
        ParagraphNode(id: Editor.createNodeId(), text: text),
      ]);

      final out = serializeDocumentToMarkdown(doc);
      expect(out, '~hello~ world');
    });
  });

  group('serializeDocumentToMarkdown', () {
    test('round-trips a single paragraph', () {
      final doc = parseMarkdownToDocument('a simple note');
      expect(serializeDocumentToMarkdown(doc), 'a simple note');
    });

    test('round-trips a heading', () {
      final doc = parseMarkdownToDocument('# Big Title');
      expect(serializeDocumentToMarkdown(doc), '# Big Title');
    });

    test('round-trips a task and keeps the id marker', () {
      const id = 'task-xyz';
      final original = '- [ ] write tests <!-- task:$id -->';
      final doc = parseMarkdownToDocument(original);
      expect(serializeDocumentToMarkdown(doc), original);
    });

    test('blank line between blocks is preserved on round-trip', () {
      const original = '# Title\n\nA paragraph after a blank line.';
      final doc = parseMarkdownToDocument(original);
      final out = serializeDocumentToMarkdown(doc);
      expect(out, original);
    });

    test('multiple paragraphs separated by blank lines are preserved', () {
      const original = 'first paragraph\n\nsecond paragraph\n\nthird';
      final doc = parseMarkdownToDocument(original);
      final out = serializeDocumentToMarkdown(doc);
      expect(out, original);
    });

    test('strikethrough round-trips', () {
      const original = 'text with ~strikethrough~ inside';
      final doc = parseMarkdownToDocument(original);
      expect(serializeDocumentToMarkdown(doc), original);
    });

    test('bold round-trips', () {
      const original = 'text with **bold** inside';
      final doc = parseMarkdownToDocument(original);
      expect(serializeDocumentToMarkdown(doc), original);
    });

    test('italic round-trips', () {
      const original = 'text with *italic* inside';
      final doc = parseMarkdownToDocument(original);
      expect(serializeDocumentToMarkdown(doc), original);
    });

    test('bold and italic on separate spans round-trip', () {
      const original = '**bold** and *italic* text';
      final doc = parseMarkdownToDocument(original);
      expect(serializeDocumentToMarkdown(doc), original);
    });

    test('bold inside strikethrough round-trips', () {
      // ~**bold-strike**~ — strikethrough wrapping bold.
      // Both attributions are preserved through parse → serialize.
      const original = '~**bold-strike**~';
      final doc = parseMarkdownToDocument(original);
      final out = serializeDocumentToMarkdown(doc);
      // The plain text must survive.
      expect(
        (doc.first as ParagraphNode).text.toPlainText(),
        'bold-strike',
      );
      // Both attributions must be present after parse.
      final text = (doc.first as ParagraphNode).text;
      final boldSpans = text.getAttributionSpansInRange(
        attributionFilter: (a) => a == boldAttribution,
        range: SpanRange(0, text.toPlainText().length),
      );
      final strikeSpans = text.getAttributionSpansInRange(
        attributionFilter: (a) => a == strikethroughAttribution,
        range: SpanRange(0, text.toPlainText().length),
      );
      expect(boldSpans, isNotEmpty, reason: 'bold attribution must survive parse');
      expect(strikeSpans, isNotEmpty, reason: 'strikethrough attribution must survive parse');
      // The serialized form must contain the markers for both attributions.
      expect(out, contains('**'), reason: 'bold marker must appear in output');
      expect(out, contains('~'), reason: 'strikethrough marker must appear in output');
    });
  });
}

Attribution? _blockType(DocumentNode node) {
  if (node is! ParagraphNode) return null;
  return node.getMetadataValue('blockType') as Attribution?;
}
