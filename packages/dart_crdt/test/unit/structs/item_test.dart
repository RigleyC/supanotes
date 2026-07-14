import 'package:dart_crdt/src/content/content.dart';
import 'package:dart_crdt/src/structs/abstract_struct.dart';
import 'package:dart_crdt/src/structs/id.dart';
import 'package:test/test.dart';

import '../../helpers/item_target.dart';

void main() {
  group('Item integration', () {
    test('inserts local content into a parent sequence', () {
      final parent = ItemParent(key: 'root');
      final target = ItemTarget();
      final item = _textItem(client: 1, clock: 0, value: 'ab', parent: parent);

      item.integrate(target);

      expect(parent.items(), [item]);
      expect(parent.length, 2);
      expect(item.countable, isTrue);
      expect(item.values, ['a', 'b']);
      expect(target.inserted.hasId(_id(1, 1)), isTrue);
      expect(target.markerUpdates.single.lengthDelta, 2);
      expect(target.changedParents.single.parent, parent);
    });

    test('orders concurrent inserts deterministically by client id', () {
      final parent = ItemParent(key: 'root');
      final target = ItemTarget();
      final highClient = _textItem(
        client: 2,
        clock: 0,
        value: 'b',
        parent: parent,
      );
      final lowClient = _textItem(
        client: 1,
        clock: 0,
        value: 'a',
        parent: parent,
      );

      highClient.integrate(target);
      lowClient.integrate(target);

      expect(parent.items(), [lowClient, highClient]);
      expect(lowClient.right, highClient);
      expect(highClient.left, lowClient);
      expect(parent.length, 2);
    });

    test('delegates deletion to content and updates parent state', () {
      final parent = ItemParent(key: 'root');
      final target = ItemTarget();
      final content = ContentDocument(guid: 'doc-1');
      final item = Item(
        id: _id(1, 0),
        parent: parent,
        content: content,
      );

      item.integrate(target);
      item.delete(target);

      expect(item.deleted, isTrue);
      expect(parent.length, 0);
      expect(target.deleted.hasId(_id(1, 0)), isTrue);
      expect(target.addedDocuments, [content.document]);
      expect(target.removedDocuments, [content.document]);
      expect(target.markerUpdates.map((update) => update.lengthDelta), [1, -1]);
    });

    test('integrates parentless content as a tombstone range', () {
      final target = ItemTarget();
      final item = _textItem(client: 1, clock: 0, value: 'abc');

      item.integrate(target);

      expect(target.structs.single, isA<GC>());
      expect(target.deleted.hasId(_id(1, 2)), isTrue);
      expect(target.inserted.hasId(_id(1, 2)), isTrue);
    });
  });

  group('Item split, merge, and redo', () {
    test('splits content, links the right item, and preserves flags', () {
      final parent = ItemParent(key: 'root');
      final target = ItemTarget();
      final item = _textItem(client: 1, clock: 0, value: 'abcd', parent: parent)
        ..keep = true
        ..redone = _id(9, 10);

      item.integrate(target);
      final right = item.split(2);

      expect(item.length, 2);
      expect(right.length, 2);
      expect(item.values, ['a', 'b']);
      expect(right.values, ['c', 'd']);
      expect(right.id, _id(1, 2));
      expect(right.origin, _id(1, 1));
      expect(right.redone, _id(9, 12));
      expect(right.keep, isTrue);
      expect(item.right, right);
      expect(parent.length, 4);
      expect(() => item.split(2), throwsRangeError);
    });

    test('merges adjacent compatible items and transfers marker flags', () {
      final parent = ItemParent(key: 'root');
      final target = ItemTarget();
      final left = _textItem(client: 1, clock: 0, value: 'ab', parent: parent);
      final right = _textItem(
        client: 1,
        clock: 2,
        value: 'cd',
        parent: parent,
        left: left,
        origin: left.lastId,
      )
        ..keep = true
        ..marker = true;

      left.integrate(target);
      right.integrate(target);

      expect(left.canMergeWith(right), isTrue);
      expect(left.mergeWith(right), isTrue);
      expect(left.length, 4);
      expect(left.values, ['a', 'b', 'c', 'd']);
      expect(left.right, isNull);
      expect(left.keep, isTrue);
      expect(left.marker, isTrue);
      expect(right.marker, isFalse);
      expect(parent.length, 4);
    });

    test('follows redo chains while preserving the inner offset', () {
      final target = ItemTarget();
      final original = _textItem(client: 1, clock: 0, value: 'abcde')
        ..redone = _id(2, 10);
      final redone = _textItem(client: 2, clock: 10, value: 'vwxyz');

      target
        ..addStruct(original)
        ..addStruct(redone);
      final result = followRedone(target, _id(1, 2));

      expect(result.item, redone);
      expect(result.diff, 2);
      expect(() => followRedone(target, _id(3, 0)), throwsStateError);
    });
  });
}

Item _textItem({
  required int client,
  required int clock,
  required String value,
  ItemParent? parent,
  Item? left,
  Id? origin,
}) {
  return Item(
    id: _id(client, clock),
    left: left,
    origin: origin,
    parent: parent,
    content: ContentString(value),
  );
}

Id _id(int client, int clock) {
  return Id(client: ClientId(client), clock: Clock(clock));
}
