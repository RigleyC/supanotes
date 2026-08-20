import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/notes/editor/document/note_document_codec.dart';

void main() {
  test('Dart codec matches the shared canonical document corpus', () {
    final corpus =
        jsonDecode(
              File('contracts/note_document/corpus.json').readAsStringSync(),
            )
            as List<dynamic>;

    for (final rawCase in corpus) {
      final testCase = Map<String, dynamic>.from(rawCase as Map);
      final document = Map<String, dynamic>.from(testCase['document'] as Map);
      final valid = testCase['valid'] as bool;
      Object? error;
      try {
        const NoteDocumentCodec().parseSnapshot(document);
      } on Object catch (caught) {
        error = caught;
      }

      expect(
        error == null,
        valid,
        reason: '${testCase['name']}: unexpected corpus result',
      );
    }
  });

  test('round-trips a rich link block with preview metadata', () {
    const codec = NoteDocumentCodec();
    final snapshot = codec.parseSnapshot({
      'schemaVersion': 1,
      'blocks': [
        {
          'id': 'link-1',
          'type': 'rich_link',
          'delta': <Map<String, dynamic>>[],
          'metadata': {
            'url': 'https://example.com/post',
            'title': 'Example',
            'description': 'A safe link',
            'imageUrl': 'https://example.com/image.jpg',
            'domain': 'example.com',
          },
        },
      ],
    });

    final encoded = codec.encodeDocument(snapshot.toMutableDocument());

    expect(encoded, hasLength(1));
    expect(encoded.single, {
      'id': 'link-1',
      'type': 'rich_link',
      'delta': <Map<String, dynamic>>[],
      'metadata': {
        'url': 'https://example.com/post',
        'title': 'Example',
        'description': 'A safe link',
        'imageUrl': 'https://example.com/image.jpg',
        'domain': 'example.com',
      },
    });
  });

  test('accepts a rich link fallback with only URL and domain', () {
    const codec = NoteDocumentCodec();

    final snapshot = codec.parseSnapshot({
      'schemaVersion': 1,
      'blocks': [
        {
          'id': 'link-1',
          'type': 'rich_link',
          'delta': <Map<String, dynamic>>[],
          'metadata': {
            'url': 'https://example.com/post',
            'domain': 'example.com',
          },
        },
      ],
    });

    expect(snapshot.blocks.single.metadata, {
      'url': 'https://example.com/post',
      'domain': 'example.com',
    });
  });
}
