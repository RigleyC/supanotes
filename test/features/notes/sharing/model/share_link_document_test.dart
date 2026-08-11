import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';

import 'package:supanotes/features/notes/editor/document/attachment_nodes.dart';
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
              {
                'insert': ' world',
                'attributes': {'bold': true},
              },
            ],
            'metadata': {},
          },
        ],
      },
    });

    expect(document.snapshot.blocks.single.id, 'block-1');
    expect(document.snapshot.blocks.single.text, 'Hello world');
    expect(document.snapshot.blocks.single.delta, hasLength(2));
    expect(document.snapshot.toJson()['schemaVersion'], 1);
    expect(document.snapshot.toJson()['blocks'], hasLength(1));
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
        'document': {
          'schemaVersion': 1,
          'blocks': [{}],
        },
      }),
      throwsFormatException,
    );
  });

  test('rejects unsupported blocks, duplicate ids, and non-text deltas', () {
    const base = {
      'title': 'Shared note',
      'document': {
        'schemaVersion': 1,
        'blocks': [
          {'id': 'block-1', 'type': 'unknown', 'delta': [], 'metadata': {}},
        ],
      },
    };
    expect(() => ShareLinkDocument.fromJson(base), throwsFormatException);

    expect(
      () => ShareLinkDocument.fromJson({
        'title': 'Shared note',
        'document': {
          'schemaVersion': 1,
          'blocks': [
            {
              'id': 'block-1',
              'type': 'paragraph',
              'delta': [
                {'insert': 'one'},
              ],
            },
            {
              'id': 'block-1',
              'type': 'paragraph',
              'delta': [
                {'insert': 'two'},
              ],
            },
          ],
        },
      }),
      throwsFormatException,
    );

    expect(
      () => ShareLinkDocument.fromJson({
        'title': 'Shared note',
        'document': {
          'schemaVersion': 1,
          'blocks': [
            {
              'id': 'block-1',
              'type': 'paragraph',
              'delta': [
                {'insert': <String, dynamic>{}},
              ],
            },
          ],
        },
      }),
      throwsFormatException,
    );
  });

  test('rejects metadata that could crash canonical decoding', () {
    for (final block in const [
      {
        'id': 'link-1',
        'type': 'rich_link',
        'delta': [],
        'metadata': {'url': 42},
      },
      {
        'id': 'task-1',
        'type': 'task',
        'delta': [
          {'insert': 'Task'},
        ],
        'metadata': {'isCompleted': 'yes'},
      },
      {
        'id': 'list-1',
        'type': 'bulletList',
        'delta': [
          {'insert': 'Item'},
        ],
        'metadata': {'indent': 'one'},
      },
      {
        'id': 'task-2',
        'type': 'task',
        'delta': [
          {'insert': 'Task'},
        ],
        'metadata': {'recurrenceRule': 7},
      },
      {
        'id': 'task-3',
        'type': 'task',
        'delta': [
          {'insert': 'Task'},
        ],
        'metadata': {'hasTime': 'yes'},
      },
    ]) {
      expect(
        () => ShareLinkDocument.fromJson({
          'title': 'Shared note',
          'document': {
            'schemaVersion': 1,
            'blocks': [block],
          },
        }),
        throwsFormatException,
      );
    }
  });

  test('converts the canonical snapshot to the Super Editor document', () {
    final document = ShareLinkDocument.fromJson(const {
      'title': 'Shared note',
      'document': {
        'schemaVersion': 1,
        'blocks': [
          {
            'id': 'header-1',
            'type': 'header1',
            'delta': [
              {'insert': 'Heading'},
            ],
            'metadata': {},
          },
          {
            'id': 'link-1',
            'type': 'rich_link',
            'delta': [],
            'metadata': {
              'url': 'https://example.com',
              'title': 'Example',
              'description': 'A safe link',
              'domain': 'example.com',
            },
          },
        ],
      },
    });

    final mutableDocument = document.snapshot.toMutableDocument();

    expect(mutableDocument.getNodeById('header-1'), isA<ParagraphNode>());
    expect(mutableDocument.getNodeById('link-1'), isA<RichLinkNode>());
    expect(
      (mutableDocument.getNodeById('link-1')! as RichLinkNode).domain,
      'example.com',
    );
  });
}
