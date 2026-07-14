import 'package:dart_crdt/src/content/content.dart';
import 'package:dart_crdt/src/metadata/id_range.dart';
import 'package:dart_crdt/src/structs/abstract_struct.dart';
import 'package:dart_crdt/src/structs/id.dart';
import 'package:dart_crdt/src/structs/struct_store.dart';
import 'package:test/test.dart' hide Skip;

void main() {
  group('StructStore slicesWithoutSplitting', () {
    test('returns stable overlapping slices without mutating structs', () {
      final parent = ItemParent(key: 'root');
      final item = _item(1, 0, 'abcd', parent);
      final gc = _gc(1, 4, 3);
      final store = StructStore()
        ..add(item)
        ..add(gc);

      final slices = store.slicesWithoutSplitting(
        client: ClientId(1),
        range: _range(1, 4),
      );

      expect(slices.map((slice) => slice.struct).toList(), [item, gc]);
      expect(slices.map((slice) => slice.offset).toList(), [1, 0]);
      expect(slices.map((slice) => slice.length).toList(), [3, 1]);
      expect(slices.map((slice) => slice.range).toList(), [
        _range(1, 3),
        _range(4, 1),
      ]);
      expect(item.length, 4);
      expect(store.structsFor(ClientId(1)), [item, gc]);
      expect(
        () => slices.add(StructSlice(struct: item, offset: 0, length: 1)),
        throwsUnsupportedError,
      );
    });

    test('handles missing clients and empty ranges', () {
      final store = StructStore();

      expect(
        store.slicesWithoutSplitting(client: ClientId(1), range: _range(0, 0)),
        isEmpty,
      );
      expect(
        store.slicesWithoutSplitting(client: ClientId(9), range: _range(0, 2)),
        isEmpty,
      );
    });
  });

  group('StructStore structsWithSplitting', () {
    test('returns exact boundary structs without extra splits', () {
      final parent = ItemParent(key: 'root');
      final item = _item(1, 0, 'ab', parent);
      final gc = _gc(1, 2, 2);
      final skip = Skip(id: _id(1, 4), length: 2);
      final store = StructStore()
        ..add(item)
        ..add(gc)
        ..add(skip);

      final structs = store.structsWithSplitting(
        client: ClientId(1),
        range: _range(0, 6),
      );

      expect(structs, [item, gc, skip]);
      expect(store.structsFor(ClientId(1)), [item, gc, skip]);
      expect(store.debugIntegrityErrors(), isEmpty);
    });

    test('splits partial item, GC, and skip overlaps at range boundaries', () {
      final parent = ItemParent(key: 'root');
      final item = _item(1, 0, 'abcd', parent);
      final gc = _gc(1, 4, 3);
      final skip = Skip(id: _id(1, 7), length: 3);
      final store = StructStore()
        ..add(item)
        ..add(gc)
        ..add(skip);

      final structs = store.structsWithSplitting(
        client: ClientId(1),
        range: _range(1, 7),
      );

      expect(structs.map((struct) => struct.range).toList(), [
        _range(1, 3),
        _range(4, 3),
        _range(7, 1),
      ]);
      expect(store.structsFor(ClientId(1)).map((struct) => struct.range), [
        _range(0, 1),
        _range(1, 3),
        _range(4, 3),
        _range(7, 1),
        _range(8, 2),
      ]);
      expect((structs.first as Item).values, ['b', 'c', 'd']);
      expect(structs[1], isA<GC>());
      expect(structs[2], isA<Skip>());
      expect(store.debugIntegrityErrors(), isEmpty);
    });
  });

  group('StructStore clean boundaries', () {
    test('cleanStart and cleanEnd split items in-place', () {
      final parent = ItemParent(key: 'root');
      final item = _item(1, 0, 'abcd', parent);
      final store = StructStore()..add(item);

      final right = store.cleanStart(_id(1, 2));
      final left = store.cleanEnd(_id(1, 0));

      expect(right.id, _id(1, 2));
      expect(right.length, 2);
      expect(left.id, _id(1, 0));
      expect(left.length, 1);
      expect(store.structsFor(ClientId(1)).map((struct) => struct.range), [
        _range(0, 1),
        _range(1, 1),
        _range(2, 2),
      ]);
      expect(() => store.cleanStart(_id(1, 4)), throwsStateError);
      expect(() => store.cleanEnd(_id(2, 0)), throwsStateError);
    });

    test('returned slice metadata remains stable after later mutation', () {
      final parent = ItemParent(key: 'root');
      final item = _item(1, 0, 'abcd', parent);
      final store = StructStore()..add(item);
      final slices = store.slicesWithoutSplitting(
        client: ClientId(1),
        range: _range(0, 4),
      );

      store.cleanStart(_id(1, 1));

      expect(slices.single.struct, item);
      expect(slices.single.offset, 0);
      expect(slices.single.length, 4);
      expect(item.length, 1);
    });
  });
}

Item _item(int client, int clock, String value, ItemParent parent) {
  return Item(
    id: _id(client, clock),
    parent: parent,
    content: ContentString(value),
  );
}

GC _gc(int client, int clock, int length) {
  return GC(id: _id(client, clock), length: length);
}

Id _id(int client, int clock) {
  return Id(client: ClientId(client), clock: Clock(clock));
}

IdRange _range(int start, int length) {
  return IdRange(start: Clock(start), length: length);
}
