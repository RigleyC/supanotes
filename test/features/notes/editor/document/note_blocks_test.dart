import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/notes/editor/document/note_blocks.dart';
import 'package:supanotes/features/notes/editor/sync/note_operation_contract.dart';

List<NoteBlock> _apply(List<NoteBlock> before, List<NoteBlockOperation> ops) {
  final blocks = List<NoteBlock>.of(before);
  for (final op in ops) {
    applyNoteOperation(
      blocks,
      kind: op.kind,
      blockId: op.blockId,
      payload: op.payload,
    );
  }
  return blocks;
}

NoteBlock _p(String id, String text, {Map<String, dynamic>? attrs}) =>
    NoteBlock(
      id: id,
      type: 'paragraph',
      delta: [
        if (text.isNotEmpty) {'insert': text, 'attributes': ?attrs},
      ],
    );

void main() {
  group('diffNoteBlocks', () {
    test('typing produces one text_delta for the edited block', () {
      final before = [_p('a', 'Hello'), _p('b', 'World')];
      final after = [_p('a', 'Hello!'), _p('b', 'World')];

      final ops = diffNoteBlocks(before, after);

      expect(ops, hasLength(1));
      expect(ops.single.kind, NoteOperationWireNames.textDelta);
      expect(ops.single.payload['ops'], [
        {'retain': 5},
        {'insert': '!'},
      ]);
      expect(_apply(before, ops), after);
    });

    test('inserting a block does not report the following blocks as moved', () {
      final before = [_p('a', '1'), _p('b', '2'), _p('c', '3')];
      final after = [_p('a', '1'), _p('n', 'new'), _p('b', '2'), _p('c', '3')];

      final ops = diffNoteBlocks(before, after);

      expect(ops.map((op) => op.kind), [NoteOperationWireNames.createBlock]);
      expect(ops.single.payload['afterBlockId'], 'a');
      expect(_apply(before, ops), after);
    });

    test('swapping two blocks yields a single move', () {
      final before = [_p('a', '1'), _p('b', '2'), _p('c', '3')];
      final after = [_p('b', '2'), _p('a', '1'), _p('c', '3')];

      final ops = diffNoteBlocks(before, after);

      expect(ops, hasLength(1));
      expect(ops.single.kind, NoteOperationWireNames.moveBlock);
      expect(_apply(before, ops), after);
    });

    test('formatting change becomes an attribute-only text_delta', () {
      final before = [_p('a', 'Hello')];
      final after = [
        NoteBlock(
          id: 'a',
          type: 'paragraph',
          delta: const [
            {
              'insert': 'Hel',
              'attributes': {'bold': true},
            },
            {'insert': 'lo'},
          ],
        ),
      ];

      final ops = diffNoteBlocks(before, after);

      expect(ops.single.kind, NoteOperationWireNames.textDelta);
      expect(_apply(before, ops), after);
    });

    test('completing one occurrence is its own operation', () {
      final task = NoteBlock(
        id: 't',
        type: 'task',
        delta: const [
          {'insert': 'Pay'},
        ],
        metadata: const {
          'dueDate': '2026-09-16T09:00:00.000',
          'recurrenceRule': 'daily',
        },
      );
      final done = task.copyWith(
        metadata: {
          ...task.metadata,
          'completions': {
            '2026-09-16T09:00:00.000': '2026-09-16T12:00:00.000Z',
          },
        },
      );

      final ops = diffNoteBlocks([task], [done]);

      expect(ops.map((op) => op.kind), [
        NoteOperationWireNames.completeTaskOccurrence,
      ]);
      expect(_apply([task], ops), [done]);
    });

    test('random edits always replay to the target document', () {
      final random = Random(42);
      const words = ['a', 'bb', 'ccc', 'Olá', ' ', 'ção', '😀'];
      const types = ['paragraph', 'header1', 'quote', 'bulletList', 'task'];

      NoteBlock randomBlock(String id) {
        final ops = <Map<String, dynamic>>[];
        for (var i = random.nextInt(4); i > 0; i--) {
          final attrs = random.nextInt(3) == 0 ? {'bold': true} : null;
          ops.add({
            'insert': words[random.nextInt(words.length)],
            'attributes': ?attrs,
          });
        }
        return NoteBlock(
          id: id,
          type: types[random.nextInt(types.length)],
          delta: _normalized(ops),
          metadata: random.nextBool()
              ? const {}
              : {'indent': random.nextInt(3)},
        );
      }

      var nextId = 0;
      for (var round = 0; round < 3000; round++) {
        final before = [
          for (var i = random.nextInt(6) + 1; i > 0; i--)
            randomBlock('b${nextId++}'),
        ];
        final after = <NoteBlock>[];
        for (final block in before) {
          final roll = random.nextInt(6);
          if (roll == 0) continue; // deleted
          if (roll == 1) {
            after.add(randomBlock(block.id)); // edited in place
          } else {
            after.add(block);
          }
          if (random.nextInt(4) == 0) after.add(randomBlock('b${nextId++}'));
        }
        after.shuffle(random);
        if (after.isEmpty) after.add(randomBlock('b${nextId++}'));

        final ops = diffNoteBlocks(before, after);
        final replayed = _apply(before, ops);
        // The projector keeps at least one block; mirror that rule.
        expect(
          replayed,
          after,
          reason: 'round $round\nbefore=$before\nafter=$after',
        );
      }
    });
  });

  group('applyNoteOperation', () {
    test('ignores a text change that reaches past the end', () {
      final blocks = [_p('a', 'Hi')];
      applyNoteOperation(
        blocks,
        kind: NoteOperationWireNames.textDelta,
        blockId: 'a',
        payload: const {
          'ops': [
            {'retain': 5},
            {'insert': '!'},
          ],
        },
      );
      expect(blocks.single.text, 'Hi');
    });

    test('metadata null removes a key', () {
      final blocks = [
        NoteBlock(
          id: 't',
          type: 'task',
          metadata: const {
            'dueDate': '2026-09-16T09:00:00.000',
            'hasTime': true,
          },
        ),
      ];
      applyNoteOperation(
        blocks,
        kind: NoteOperationWireNames.setBlockMetadata,
        blockId: 't',
        payload: const {
          'metadata': {'dueDate': null},
        },
      );
      expect(blocks.single.metadata, {'hasTime': true});
    });

    test('legacy heading paragraphs and link attributes are normalized', () {
      final block = NoteBlock.fromJson(const {
        'id': 'h',
        'type': 'paragraph',
        'delta': [
          {
            'insert': 'Site',
            'attributes': {'link:https://a.dev': true},
          },
        ],
        'metadata': {'blockType': 'header2'},
      });
      expect(block.type, 'header2');
      expect(block.metadata, isEmpty);
      expect(block.delta.single['attributes'], {'link': 'https://a.dev'});
    });
  });
}

/// Merges adjacent inserts with equal attributes, as a delta library does.
List<Map<String, dynamic>> _normalized(List<Map<String, dynamic>> ops) {
  final result = <Map<String, dynamic>>[];
  for (final op in ops) {
    if (result.isNotEmpty &&
        _sameAttributes(result.last['attributes'], op['attributes'])) {
      result.last = {
        ...result.last,
        'insert': '${result.last['insert']}${op['insert']}',
      };
    } else {
      result.add(op);
    }
  }
  return result;
}

bool _sameAttributes(Object? a, Object? b) =>
    (a == null && b == null) ||
    (a is Map &&
        b is Map &&
        a.length == b.length &&
        a.entries.every((e) => b[e.key] == e.value));
