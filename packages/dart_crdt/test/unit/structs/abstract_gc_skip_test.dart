import 'package:dart_crdt/src/binary/byte_writer.dart';
import 'package:dart_crdt/src/metadata/id_range.dart';
import 'package:dart_crdt/src/metadata/id_set.dart';
import 'package:dart_crdt/src/structs/abstract_struct.dart';
import 'package:dart_crdt/src/structs/id.dart';
import 'package:test/test.dart' hide Skip;

void main() {
  group('AbstractStruct validation', () {
    test('validates positive lengths and clock bounds', () {
      expect(GC(id: _id(1, 0), length: 1).range, _range(0, 1));
      expect(Skip(id: _id(1, 0), length: 1).end, 1);
      expect(() => GC(id: _id(1, 0), length: 0), throwsRangeError);
      expect(() => Skip(id: _id(1, 0), length: -1), throwsRangeError);
    });

    test('adds covered ids to id sets', () {
      final set = IdSet();
      final struct = GC(id: _id(3, 4), length: 2);

      struct.addToIdSet(set);

      expect(set.hasId(_id(3, 4)), isTrue);
      expect(set.hasId(_id(3, 5)), isTrue);
      expect(set.hasId(_id(3, 6)), isFalse);
    });
  });

  group('GC', () {
    test('has deleted semantics and writes exact binary lengths', () {
      final struct = GC(id: _id(1, 2), length: 5);
      final writer = ByteWriter();

      struct.write(writer, offset: 1, offsetEnd: 2);

      expect(struct.ref, structGcRefNumber);
      expect(struct.deleted, isTrue);
      expect(struct.isItem, isFalse);
      expect(writer.toBytes(), [structGcRefNumber, 2]);
      expect(() => struct.write(ByteWriter(), offset: 5), throwsRangeError);
    });

    test('merges only adjacent tombstones of the same client', () {
      final left = GC(id: _id(1, 0), length: 2);
      final right = GC(id: _id(1, 2), length: 3);
      final otherClient = GC(id: _id(2, 5), length: 1);

      expect(left.mergeWith(right), isTrue);
      expect(left.length, 5);
      expect(left.mergeWith(otherClient), isFalse);
      expect(left.length, 5);
      expect(left.mergeWith(Skip(id: _id(1, 5), length: 1)), isFalse);
    });

    test('splits and integrates tombstone side effects', () {
      final target = _StructTarget();
      final left = GC(id: _id(1, 0), length: 5);
      final right = left.split(2);

      right.integrate(target, offset: 1);

      expect(left.range, _range(0, 2));
      expect(right.range, _range(3, 2));
      expect(target.structs, [right]);
      expect(target.inserted.hasId(_id(1, 3)), isTrue);
      expect(target.deleted.hasId(_id(1, 4)), isTrue);
      expect(target.skipped.isEmpty, isTrue);
    });
  });

  group('Skip', () {
    test('has pending-range semantics and writes exact binary lengths', () {
      final struct = Skip(id: _id(1, 2), length: 5);
      final writer = ByteWriter();

      struct.write(writer, offset: 2);

      expect(struct.ref, structSkipRefNumber);
      expect(struct.deleted, isFalse);
      expect(struct.isItem, isFalse);
      expect(writer.toBytes(), [structSkipRefNumber, 3]);
    });

    test('merges only adjacent skips of the same client', () {
      final left = Skip(id: _id(1, 0), length: 2);
      final right = Skip(id: _id(1, 2), length: 3);

      expect(left.canMergeWith(right), isTrue);
      expect(left.mergeWith(right), isTrue);
      expect(left.length, 5);
      expect(left.mergeWith(GC(id: _id(1, 5), length: 1)), isFalse);
    });

    test('splits and integrates skip side effects', () {
      final target = _StructTarget();
      final left = Skip(id: _id(4, 10), length: 6);
      final right = left.split(4);

      right.integrate(target);

      expect(left.range, _range(10, 4));
      expect(right.range, _range(14, 2));
      expect(target.structs, [right]);
      expect(target.skipped.hasId(_id(4, 14)), isTrue);
      expect(target.inserted.isEmpty, isTrue);
      expect(target.deleted.isEmpty, isTrue);
      expect(() => right.split(2), throwsRangeError);
    });
  });
}

Id _id(int client, int clock) {
  return Id(client: ClientId(client), clock: Clock(clock));
}

IdRange _range(int start, int length) {
  return IdRange(start: Clock(start), length: length);
}

final class _StructTarget implements StructIntegrationTarget {
  final structs = <AbstractStruct>[];
  final inserted = IdSet();
  final deleted = IdSet();
  final skipped = IdSet();

  @override
  void addDeletedRange(ClientId client, IdRange range) {
    deleted.addRange(client, range);
  }

  @override
  void addInsertedRange(ClientId client, IdRange range) {
    inserted.addRange(client, range);
  }

  @override
  void addSkippedRange(ClientId client, IdRange range) {
    skipped.addRange(client, range);
  }

  @override
  void addStruct(AbstractStruct struct) {
    structs.add(struct);
  }
}
