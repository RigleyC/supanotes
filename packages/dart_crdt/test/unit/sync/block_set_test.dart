import 'package:dart_crdt/src/binary/byte_reader.dart';
import 'package:dart_crdt/src/binary/byte_writer.dart';
import 'package:dart_crdt/src/structs/id.dart';
import 'package:dart_crdt/src/sync/block_set.dart';
import 'package:test/test.dart';

void main() {
  group('BlockRange', () {
    test('validates bounds and slices suffix ranges', () {
      final range = _range(2, 5);

      expect(range.end, 7);
      expect(range.suffixFrom(Clock(0)), range);
      expect(range.suffixFrom(Clock(4)), _range(4, 3));
      expect(range.suffixFrom(Clock(7)), isNull);
      expect(() => BlockRange(start: Clock(1), length: -1), throwsRangeError);
    });
  });

  group('BlockSet', () {
    test('round-trips empty sets', () {
      final blocks = BlockSet();
      final writer = ByteWriter();

      blocks.write(writer);

      expect(blocks.isEmpty, isTrue);
      expect(writer.toBytes(), [0]);
      expect(BlockSet.read(ByteReader(writer.toBytes())), blocks);
      expect(decodeBlockSet(encodeBlockSet(blocks)), blocks);
    });

    test('groups overlapping and touching blocks by client', () {
      final blocks = BlockSet()
        ..add(_id(1, 5), length: 2)
        ..add(_id(1, 2), length: 3)
        ..addRange(ClientId(1), _range(6, 4))
        ..add(_id(2, 0))
        ..add(_id(1, 0), length: 0);

      expect(blocks.rangesFor(ClientId(1)), [_range(2, 8)]);
      expect(blocks.rangesFor(ClientId(2)), [_range(0, 1)]);
      expect(blocks.toIdSet().hasId(_id(1, 9)), isTrue);
      expect(blocks.toIdSet().hasId(_id(1, 10)), isFalse);
    });

    test('iterates and writes clients in deterministic descending order', () {
      final blocks = BlockSet()
        ..add(_id(1, 0))
        ..add(_id(3, 2), length: 2)
        ..add(_id(2, 4));
      final visited = <String>[];
      final writer = ByteWriter();

      blocks
        ..forEach(
          (client, range) => visited.add(
            '${client.value}:${range.start.value}+${range.length}',
          ),
        )
        ..write(writer);

      expect(blocks.clients, [ClientId(3), ClientId(2), ClientId(1)]);
      expect(visited, ['3:2+2', '2:4+1', '1:0+1']);
      expect(writer.toBytes(), [3, 3, 1, 2, 2, 2, 1, 4, 1, 1, 1, 0, 1]);
    });

    test('excludes duplicate ranges using known state vectors', () {
      final blocks = BlockSet()
        ..add(_id(1, 0), length: 5)
        ..add(_id(2, 3), length: 4)
        ..add(_id(3, 0), length: 2);
      final excluded = blocks.excludeKnown({
        ClientId(1): Clock(2),
        ClientId(2): Clock(10),
      });

      expect(excluded.rangesFor(ClientId(1)), [_range(2, 3)]);
      expect(excluded.rangesFor(ClientId(2)), isEmpty);
      expect(excluded.rangesFor(ClientId(3)), [_range(0, 2)]);
      expect(excluded.stateVector(), {
        ClientId(1): Clock(5),
        ClientId(3): Clock(2),
      });
    });

    test('merges sets, excludes duplicates, and round-trips binary bytes', () {
      final left = BlockSet()
        ..add(_id(1, 0), length: 4)
        ..add(_id(2, 5));
      final right = BlockSet()
        ..add(_id(1, 2), length: 4)
        ..add(_id(3, 0));
      final merged = left.merged(right);
      final unique = merged.excludeKnown({
        ClientId(1): Clock(3),
        ClientId(2): Clock(6),
      });

      expect(merged.rangesFor(ClientId(1)), [_range(0, 6)]);
      expect(unique.rangesFor(ClientId(1)), [_range(3, 3)]);
      expect(unique.rangesFor(ClientId(2)), isEmpty);
      expect(unique.rangesFor(ClientId(3)), [_range(0, 1)]);
      expect(decodeBlockSet(encodeBlockSet(merged)), merged);
    });
  });
}

Id _id(int client, int clock) {
  return Id(client: ClientId(client), clock: Clock(clock));
}

BlockRange _range(int start, int length) {
  return BlockRange(start: Clock(start), length: length);
}
