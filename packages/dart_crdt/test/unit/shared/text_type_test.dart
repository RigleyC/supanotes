import 'package:dart_crdt/src/content/content.dart';
import 'package:dart_crdt/src/delta/delta_operation.dart';
import 'package:dart_crdt/src/doc/doc.dart';
import 'package:test/test.dart';

void main() {
  group('SharedType text APIs', () {
    test('inserts, deletes, and renders basic text', () {
      final text = SharedType(kind: SharedTypeKind.text)
        ..insertText(0, 'Hello')
        ..insertText(5, ' world')
        ..deleteText(5, 1)
        ..insertText(5, ',');

      expect(text.length, 11);
      expect(text.toPlainText(), 'Hello,world');
      expect(text.toString(), 'Hello,world');
      expect(
        text.toArray(),
        ['H', 'e', 'l', 'l', 'o', ',', 'w', 'o', 'r', 'l', 'd'],
      );
    });

    test('handles surrogate pairs as one text position', () {
      final text = SharedType(kind: SharedTypeKind.text)
        ..insertText(0, 'A😀B')
        ..deleteText(1, 1);

      expect(text.length, 2);
      expect(text.toPlainText(), 'AB');
      expect(text.toDelta().toJson(), {
        'ops': [
          {'insert': 'AB'},
        ],
      });
    });

    test('formats text and removes falsy formats with null attributes', () {
      final text = SharedType(kind: SharedTypeKind.text)
        ..insertText(0, 'abc')
        ..format(0, 3, DeltaAttributes.fromJson({'bold': false, 'size': 0}))
        ..format(1, 1, DeltaAttributes.fromJson({'bold': null}));

      expect(text.toDelta().toJson(), {
        'ops': [
          {
            'insert': 'a',
            'attributes': {'bold': false, 'size': 0},
          },
          {
            'insert': 'b',
            'attributes': {'size': 0},
          },
          {
            'insert': 'c',
            'attributes': {'bold': false, 'size': 0},
          },
        ],
      });
    });

    test('applies multiline deltas and renders retained formatting', () {
      final text = SharedType(kind: SharedTypeKind.text)
        ..insertText(0, 'one\ntwo\n')
        ..applyDelta(
          Delta([
            DeltaRetain(
              length: 4,
              attributes: DeltaAttributes.fromJson({'header': 1}),
            ),
          ]),
        );

      expect(text.toPlainText(), 'one\ntwo\n');
      expect(text.toDelta().toJson(), {
        'ops': [
          {
            'insert': 'one\n',
            'attributes': {'header': 1},
          },
          {'insert': 'two\n'},
        ],
      });
    });

    test('supports embeds and nested shared types as text positions', () {
      final text = SharedType(kind: SharedTypeKind.text);
      final embed = SharedType(kind: SharedTypeKind.map, name: 'card');

      text
        ..insertText(0, 'A')
        ..insertEmbed(1, {'image': 'hash'})
        ..insertEmbed(2, embed)
        ..insertText(3, 'B');

      expect(text.length, 4);
      expect(text.toPlainText(), 'A\uFFFC\uFFFCB');
      expect(embed.parent, same(text));
      expect(embed.parentKey, 2);
      expect(text.toDelta().toJson(), {
        'ops': [
          {'insert': 'A'},
          {
            'insert': [
              {'image': 'hash'},
            ],
          },
          {
            'insert': [
              {'kind': 'map', 'name': 'card'},
            ],
          },
          {'insert': 'B'},
        ],
      });
    });

    test('sets transaction formatting cleanup hooks', () {
      final doc = Doc();
      final text = doc.get('body', SharedTypeKind.text)..insertText(0, 'abc');
      late final Transaction transaction;

      doc.transact((current) {
        transaction = current;
        text.format(0, 1, DeltaAttributes.fromJson({'bold': true}));
      });

      expect(transaction.shouldCleanupFormatting, isTrue);
      expect(transaction.changed[text], {0});
    });
  });
}
