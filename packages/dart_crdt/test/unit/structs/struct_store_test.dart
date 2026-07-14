import 'package:dart_crdt/src/content/content.dart';
import 'package:dart_crdt/src/metadata/id_range.dart';
import 'package:dart_crdt/src/metadata/id_set.dart';
import 'package:dart_crdt/src/structs/abstract_struct.dart';
import 'package:dart_crdt/src/structs/id.dart';
import 'package:dart_crdt/src/structs/pending_update.dart';
import 'package:dart_crdt/src/structs/struct_store.dart';
import 'package:dart_crdt/src/sync/block_set.dart';
import 'package:test/test.dart' hide Skip;

void main() {
  group('StructStore empty and lookup behavior', () {
    test('returns empty snapshots and zero clocks for missing clients', () {
      final store = StructStore();

      expect(store.isEmpty, isTrue);
      expect(store.clients, isEmpty);
      expect(store.clientCount, 0);
      expect(store.getClock(ClientId(1)), Clock(0));
      expect(store.stateVector(), isEmpty);
      expect(store.structsFor(ClientId(1)), isEmpty);
      expect(store.structContaining(_id(1, 0)), isNull);
      expect(store.itemContaining(_id(1, 0)), isNull);
      expect(
        () => store.structsFor(ClientId(1)).add(_gc(1, 0, 1)),
        throwsUnsupportedError,
      );
    });

    test('finds structs by start and containing clock boundaries', () {
      final parent = ItemParent(key: 'root');
      final item = _item(1, 0, 'ab', parent);
      final tombstone = _gc(1, 2, 3);
      final other = _item(2, 4, 'z', parent);
      final store = StructStore()
        ..add(item)
        ..add(tombstone)
        ..add(other);

      expect(store.clients, [ClientId(1), ClientId(2)]);
      expect(store.getClock(ClientId(1)), Clock(5));
      expect(store.getClock(ClientId(2)), Clock(5));
      expect(
        store.stateVector(),
        {ClientId(1): Clock(5), ClientId(2): Clock(5)},
      );
      expect(store.structAtStart(_id(1, 0)), item);
      expect(store.structAtStart(_id(1, 1)), isNull);
      expect(store.structContaining(_id(1, 1)), item);
      expect(store.structContaining(_id(1, 4)), tombstone);
      expect(store.structContaining(_id(1, 5)), isNull);
      expect(store.itemContaining(_id(1, 1)), item);
      expect(store.itemContaining(_id(1, 2)), isNull);
      expect(store.getStruct(_id(2, 4)), other);
      expect(() => store.getStruct(_id(3, 0)), throwsStateError);
    });
  });

  group('StructStore skips and pending state', () {
    test('tracks skips and replaces ranges inside integrated skips', () {
      final parent = ItemParent(key: 'root');
      final store = StructStore()
        ..add(_item(1, 0, 'ab', parent))
        ..add(Skip(id: _id(1, 2), length: 5));
      final replacement = _gc(1, 3, 2);

      store.add(replacement);

      expect(
        store.structsFor(ClientId(1)).map((struct) => struct.range).toList(),
        [_range(0, 2), _range(2, 1), _range(3, 2), _range(5, 2)],
      );
      expect(store.structContaining(_id(1, 3)), replacement);
      expect(store.skips.rangesFor(ClientId(1)), [_range(2, 1), _range(5, 2)]);
      expect(store.getClock(ClientId(1)), Clock(7));
      expect(store.stateVector(), {ClientId(1): Clock(2)});
    });

    test('records pending structs, pending deletes, and target side effects',
        () {
      final pendingDeletes = IdSet()..add(_id(4, 1), length: 2);
      final pendingBlocks = BlockSet()..add(_id(3, 5), length: 4);
      final pendingUpdate = PendingStructs(
        missing: {ClientId(8): Clock(2)},
        update: [1, 2, 3],
      );
      final store = StructStore()
        ..addPendingStructs(pendingBlocks)
        ..addPendingDeleteSet(pendingDeletes)
        ..setPendingStructUpdate(pendingUpdate)
        ..addInsertedRange(ClientId(1), _range(0, 1))
        ..addDeletedRange(ClientId(2), _range(3, 2))
        ..addSkippedRange(ClientId(5), _range(9, 1));

      expect(store.pendingStructs, pendingBlocks);
      expect(store.pendingDeleteSet, pendingDeletes);
      expect(store.pendingStructUpdate, pendingUpdate);
      expect(store.inserted.hasId(_id(1, 0)), isTrue);
      expect(store.deleted.hasId(_id(2, 4)), isTrue);
      expect(store.skips.hasId(_id(5, 9)), isTrue);

      store
        ..clearPendingStructs()
        ..clearPendingDeleteSet();

      expect(store.pendingStructs.isEmpty, isTrue);
      expect(store.pendingDeleteSet.isEmpty, isTrue);
      expect(store.pendingStructUpdate, isNull);
    });
  });

  group('StructStore integrity checks', () {
    test('rejects non-contiguous non-skip insertion through normal APIs', () {
      final store = StructStore()..add(_gc(1, 0, 2));

      expect(() => store.add(_gc(1, 4, 1)), throwsStateError);
      expect(() => store.add(_gc(1, 1, 1)), throwsStateError);
    });

    test('reports debug integrity failures for unchecked stores', () {
      final store = StructStore.debugUnchecked({
        ClientId(1): [_gc(1, 0, 2), _gc(1, 3, 1)],
        ClientId(2): [_gc(3, 0, 1)],
      });

      expect(store.debugIntegrityErrors(), [
        'client 1 has gap before clock 3',
        'client 2 contains struct for 3',
      ]);
      expect(store.debugAssertIntegrity, throwsStateError);
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
