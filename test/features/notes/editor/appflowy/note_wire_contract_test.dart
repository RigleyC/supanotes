import 'dart:convert';
import 'dart:io';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/notes/editor/appflowy/note_appflowy_codec.dart';
import 'package:supanotes/features/notes/editor/document/note_blocks.dart';
import 'package:supanotes/features/notes/editor/document/note_document_codec.dart';
import 'package:supanotes/features/notes/editor/sync/note_operation_contract.dart';

/// What the new editor puts on the wire must stay what the server (and older
/// app versions) already understand.
void main() {
  test('blocks the editor creates match the shared create_block fixture', () {
    final fixture = jsonDecode(
      File(
        'test/fixtures/ot_create_blocks_contract.json',
      ).readAsStringSync(),
    ) as Map<String, dynamic>;
    Node withId(Node node, String id) =>
        node..updateAttributes({NoteNodeKeys.blockId: id});
    // Nodes as AppFlowy's own commands create them.
    final document = Document.blank()
      ..insert(
        [0],
        [
          withId(paragraphNode(text: 'Body'), 'paragraph'),
          withId(todoListNode(checked: false, text: 'Task text'), 'task'),
          withId(bulletedListNode(text: 'Bullet text'), 'bullet'),
          withId(
            numberedListNode(delta: Delta()..insert('Ordered text')),
            'ordered',
          ),
          withId(headingNode(level: 1, text: 'Heading'), 'header'),
          withId(quoteNode(delta: Delta()..insert('Quoted text')), 'quote'),
        ],
      );

    final created = diffNoteBlocks(
      const [],
      const NoteAppFlowyCodec().toBlocks(document),
    );

    expect(created.map((op) => op.kind).toSet(), {
      NoteOperationWireNames.createBlock,
    });
    for (final (index, expected) in (fixture['blocks'] as List).indexed) {
      final payload = Map<String, dynamic>.from(created[index].payload)
        ..remove('afterBlockId');
      final metadata = payload['metadata'] as Map? ?? const {};
      if (metadata.isEmpty) payload.remove('metadata');
      final want = Map<String, dynamic>.from(expected as Map);
      // `blockType` on tasks was redundant with the block type; only the
      // previous editor wrote it, and the server ignores it.
      (want['metadata'] as Map?)?.remove('blockType');
      expect(payload, want, reason: want['id'] as String);
      // And the payload passes the document contract.
      const NoteDocumentCodec().parseBlock(payload);
    }
  });

  test('a null attribute in a text change removes the style', () {
    expect(
      composeBlockDelta(
        const [
          {
            'insert': 'Hell',
            'attributes': {'bold': true},
          },
          {'insert': 'o'},
        ],
        const [
          {
            'retain': 5,
            'attributes': {'bold': null},
          },
        ],
      ),
      [
        {'insert': 'Hello'},
      ],
    );
  });

  test('a persisted empty delta operation still opens', () {
    final block = NoteBlock.fromJson(const {
      'id': 'p',
      'type': 'paragraph',
      'delta': [<String, dynamic>{}],
    });
    expect(block.text, isEmpty);
  });

  test('leaked mutation ops are dropped locally but rejected from sync', () {
    const codec = NoteDocumentCodec();
    const leaked = {
      'id': 'p',
      'type': 'paragraph',
      'delta': [
        {'insert': 'kept'},
        {'delete': 4},
      ],
    };
    expect(
      codec.parseBlock(leaked, allowMutationDeltaOperations: true).delta,
      [
        {'insert': 'kept'},
      ],
    );
    expect(() => codec.parseBlock(leaked), throwsFormatException);
  });
}
