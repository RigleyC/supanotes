import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';
import 'package:supanotes/features/notes/domain/node_codec.dart';
import 'package:supanotes/features/notes/domain/note_node.dart';

void main() {
  test(
    'preserves the final character of an inline attribution on round-trip',
    () {
      final spans = AttributedSpans()
        ..addAttribution(newAttribution: boldAttribution, start: 0, end: 6);
      final source = ParagraphNode(
        id: 'paragraph-1',
        text: AttributedText('Negrito', spans),
      );

      final data = NodeCodec.nodeData(source);
      final restored =
          NodeCodec.createNodeFromSchema(
                NoteNode(
                  id: source.id,
                  noteId: 'note-1',
                  position: 'a0',
                  type: 'paragraph',
                  data: data,
                  createdAt: DateTime(2026),
                  updatedAt: DateTime(2026),
                ),
              )
              as TextNode;

      expect(data['spans'], [
        {'attribution': 'bold', 'start': 0, 'end': 7},
      ]);
      expect(data['spansVersion'], 2);
      expect(
        restored.text
            .getAttributionSpansInRange(
              attributionFilter: (attribution) =>
                  attribution == boldAttribution,
              range: const SpanRange(6, 6),
            )
            .isNotEmpty,
        isTrue,
      );
    },
  );

  test(
    'reads legacy inclusive span ends without truncating the final character',
    () {
      final restored =
          NodeCodec.createNodeFromSchema(
                NoteNode(
                  id: 'paragraph-1',
                  noteId: 'note-1',
                  position: 'a0',
                  type: 'paragraph',
                  data: {
                    'text': 'Negrito',
                    'spans': [
                      {'attribution': 'bold', 'start': 0, 'end': 6},
                    ],
                  },
                  createdAt: DateTime(2026),
                  updatedAt: DateTime(2026),
                ),
              )
              as TextNode;

      expect(
        restored.text
            .getAttributionSpansInRange(
              attributionFilter: (attribution) =>
                  attribution == boldAttribution,
              range: const SpanRange(6, 6),
            )
            .isNotEmpty,
        isTrue,
      );
    },
  );
}
