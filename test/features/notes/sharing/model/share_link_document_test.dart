import 'package:flutter_test/flutter_test.dart';

import 'package:supanotes/features/notes/sharing/model/share_link_document.dart';

void main() {
  test('keeps the canonical block payload and derives its text', () {
    final document = ShareLinkDocument.fromJson(const {
      'title': 'Shared note',
      'document': {
        'schemaVersion': 1,
        'blocks': [
          {
            'id': 'block-1',
            'type': 'paragraph',
            'delta': [
              {'insert': 'Hello'},
              {'insert': ' world', 'attributes': {'bold': true}},
            ],
            'metadata': {},
          },
        ],
      },
    });

    expect(document.blocks.single.id, 'block-1');
    expect(document.blocks.single.text, 'Hello world');
    expect(document.blocks.single.delta, hasLength(2));
  });

  test('rejects a response without a canonical document', () {
    expect(
      () => ShareLinkDocument.fromJson(const {'title': 'Shared note'}),
      throwsFormatException,
    );
  });

  test('rejects malformed canonical blocks', () {
    expect(
      () => ShareLinkDocument.fromJson(const {
        'title': 'Shared note',
        'document': {'schemaVersion': 1, 'blocks': [{}]},
      }),
      throwsFormatException,
    );
  });
}
