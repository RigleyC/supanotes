import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';
import 'package:supanotes/features/notes/domain/note_document_codec.dart';

void main() {
  group('OtDocumentCodec Delta Suffix & Attribution Tests', () {
    const codec = NoteDocumentCodec();

    test(
      'retains unconsumed source text suffix after mid-text insert delta',
      () {
        final source = AttributedText('abcdef');
        final deltaOps = [
          {'retain': 3},
          {'insert': 'X'},
        ];

        final result = codec.applyDeltaToText(source, deltaOps);

        expect(result, isNotNull);
        expect(result!.toPlainText(), 'abcXdef');
      },
    );

    test(
      'retains attributions on unconsumed source text suffix after insert',
      () {
        final span = AttributedSpans();
        span.addAttribution(newAttribution: boldAttribution, start: 3, end: 6);
        final source = AttributedText('abcdef', span);

        final deltaOps = [
          {'retain': 2},
          {'insert': '123'},
        ];

        final result = codec.applyDeltaToText(source, deltaOps);

        expect(result, isNotNull);
        expect(result!.toPlainText(), 'ab123cdef');

        // Check that 'def' at indices 6..9 has bold attribution preserved
        final defMarker = result.spans.markers.where(
          (m) => m.attribution == boldAttribution,
        );
        expect(defMarker.isNotEmpty, true);
      },
    );

    test('encodes task metadata as JSON values', () {
      final node = ParagraphNode(
        id: 'task-1',
        text: AttributedText('Task'),
        metadata: {'custom': const NamedAttribution('task')},
      );

      final encoded = codec.encodeNode(node);

      expect(() => jsonEncode(encoded), returnsNormally);
      expect((encoded['metadata'] as Map)['custom'], 'task');
    });

    test(
      'encodes TaskNode metadata including hasTime, reminder, and dueDate',
      () {
        final taskNode = TaskNode(
          id: 'task-123',
          text: AttributedText('Call doctor'),
          isComplete: false,
          metadata: {
            'dueDate': '2026-07-25T14:30:00.000',
            'hasTime': true,
            'reminder': '15m_before',
            'recurrenceRule': 'weekly',
          },
        );

        final encoded = codec.encodeNode(taskNode);

        expect(encoded['type'], 'task');
        final metadata = encoded['metadata'] as Map<String, dynamic>;
        expect(metadata['isCompleted'], false);
        expect(metadata['dueDate'], '2026-07-25T14:30:00.000');
        expect(metadata['hasTime'], true);
        expect(metadata['reminder'], '15m_before');
        expect(metadata['recurrenceRule'], 'weekly');
      },
    );

    test('decodes string blockType metadata as an attribution', () {
      final node =
          codec.decodeNode({
                'id': 'paragraph-1',
                'type': 'paragraph',
                'delta': [
                  {'insert': 'Text'},
                ],
                'metadata': {'blockType': 'header1'},
              })
              as ParagraphNode;

      expect(node.getMetadataValue('blockType'), header1Attribution);
    });

    test('round trips text block types through the OT delta contract', () {
      final cases = <Map<String, dynamic>>[
        {
          'type': 'paragraph',
          'node': ParagraphNode(id: 'paragraph', text: AttributedText('Body')),
          'text': 'Body',
        },
        {
          'type': 'task',
          'node': TaskNode(
            id: 'task',
            text: AttributedText('Task text'),
            isComplete: false,
          ),
          'text': 'Task text',
        },
        {
          'type': 'bulletList',
          'node': ListItemNode.unordered(
            id: 'bullet',
            text: AttributedText('Bullet text'),
          ),
          'text': 'Bullet text',
        },
        {
          'type': 'orderedList',
          'node': ListItemNode.ordered(
            id: 'ordered',
            text: AttributedText('Ordered text'),
          ),
          'text': 'Ordered text',
        },
        {
          'type': 'header1',
          'node': ParagraphNode(
            id: 'header',
            text: AttributedText('Heading'),
            metadata: {'blockType': header1Attribution},
          ),
          'text': 'Heading',
        },
        {
          'type': 'quote',
          'node': ParagraphNode(
            id: 'quote',
            text: AttributedText('Quoted text'),
            metadata: {'blockType': blockquoteAttribution},
          ),
          'text': 'Quoted text',
        },
      ];

      for (final testCase in cases) {
        final encoded = codec.encodeNode(testCase['node'] as DocumentNode);

        expect(encoded['type'], testCase['type']);
        expect(encoded['delta'], [
          {'insert': testCase['text']},
        ]);

        final decoded = codec.decodeNode(encoded);
        expect((decoded as TextNode).text.toPlainText(), testCase['text']);
        expect(codec.encodeNode(decoded)['type'], testCase['type']);
      }
    });

    test('matches the shared create block contract fixture', () {
      final fixture =
          jsonDecode(
                File(
                  'test/fixtures/ot_create_blocks_contract.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final expectedBlocks = fixture['blocks'] as List<dynamic>;
      final nodes = <DocumentNode>[
        ParagraphNode(id: 'paragraph', text: AttributedText('Body')),
        TaskNode(
          id: 'task',
          text: AttributedText('Task text'),
          isComplete: false,
        ),
        ListItemNode.unordered(
          id: 'bullet',
          text: AttributedText('Bullet text'),
        ),
        ListItemNode.ordered(
          id: 'ordered',
          text: AttributedText('Ordered text'),
        ),
        ParagraphNode(
          id: 'header',
          text: AttributedText('Heading'),
          metadata: {'blockType': header1Attribution},
        ),
        ParagraphNode(
          id: 'quote',
          text: AttributedText('Quoted text'),
          metadata: {'blockType': blockquoteAttribution},
        ),
      ];

      expect(nodes.map(codec.encodeNode).toList(), expectedBlocks);
    });
  });
}
