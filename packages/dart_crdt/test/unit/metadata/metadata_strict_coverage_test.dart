import 'package:dart_crdt/src/binary/byte_reader.dart';
import 'package:dart_crdt/src/binary/byte_writer.dart';
import 'package:dart_crdt/src/binary/varint_codec.dart';
import 'package:dart_crdt/src/metadata/content_attribute.dart';
import 'package:dart_crdt/src/metadata/id_map.dart';
import 'package:dart_crdt/src/metadata/id_map_codec.dart';
import 'package:dart_crdt/src/metadata/id_range.dart';
import 'package:dart_crdt/src/metadata/id_ranges.dart';
import 'package:dart_crdt/src/metadata/id_set.dart';
import 'package:dart_crdt/src/metadata/id_set_codec.dart';
import 'package:dart_crdt/src/structs/id.dart';
import 'package:test/test.dart';

void main() {
  group('strict metadata coverage', () {
    test('covers optional id range branches and overflow validation', () {
      final empty = _range(1, 0);
      final filled = _range(2, 2);
      final maybeEmpty = const MaybeIdRange.empty();
      final maybeFilled = MaybeIdRange.of(filled);

      expect(empty.merge(filled), maybeFilled);
      expect(filled.merge(empty), maybeFilled);
      expect(empty.merge(empty), maybeEmpty);
      expect(maybeFilled.isPresent, isTrue);
      expect(maybeFilled.orNull, filled);
      expect(maybeEmpty, const MaybeIdRange.empty());
      expect(maybeEmpty.hashCode, maybeEmpty.hashCode);
      expect(maybeEmpty.toString(), 'empty');
      expect(
        () => IdRange(start: Clock(maxSafeInteger), length: 2),
        throwsRangeError,
      );
    });

    test('covers range-list empty, merge, diff, and break branches', () {
      final left = IdRanges([_range(0, 2), _range(10, 2)]);
      final right = IdRanges([_range(2, 1)]);

      expect(IdRanges.empty.length, 0);
      expect(IdRanges.empty.merged(left), left);
      expect(left.merged(IdRanges.empty), left);
      expect(left.slice(_range(20, 1)).isEmpty, isTrue);
      expect(left.slice(_range(1, 1)).ranges, [_range(1, 1)]);
      expect(left.diff(IdRanges([_range(0, 20)])), IdRanges.empty);
      expect(IdRanges.empty.intersect(left), IdRanges.empty);
      expect(left.merged(right).ranges, [_range(0, 3), _range(10, 2)]);
    });

    test('covers id-set empty mutations and slice branches', () {
      final set = IdSet()
        ..addRange(ClientId(1), _range(0, 2))
        ..addRange(ClientId(2), _range(5, 1));
      final byClient = set.rangesByClient;

      set
        ..addRange(ClientId(1), _range(0, 0))
        ..deleteRange(ClientId(9), _range(0, 1))
        ..deleteRange(ClientId(1), _range(0, 0));

      expect(set.isNotEmpty, isTrue);
      expect(byClient[ClientId(1)], [_range(0, 2)]);
      expect(
        () => byClient[ClientId(1)]!.add(_range(9, 1)),
        throwsUnsupportedError,
      );
      expect(
        set.slice(client: ClientId(9), range: _range(0, 1)).isEmpty,
        isTrue,
      );
      expect(
        set.slice(client: ClientId(1), range: _range(9, 1)).isEmpty,
        isTrue,
      );
      expect(
        set.intersect(IdSet()..addRange(ClientId(9), _range(0, 1))),
        IdSet(),
      );
    });

    test('covers id-set encoder closure and V2 validation', () {
      final v1 = IdSetEncoderV1();
      final v2 = IdSetEncoderV2()
        ..writeIdSetClock(Clock(2))
        ..writeIdSetLen(1);

      expect(v1.toBytes(), isEmpty);
      expect(v1.toBytes(), isEmpty);
      expect(() => v1.restWriter, throwsStateError);
      expect(() => v2.writeIdSetClock(Clock(1)), throwsRangeError);
      expect(v2.toBytes(), isNotEmpty);
      expect(() => v2.restWriter, throwsStateError);
    });

    test('covers id-map empty, missing, pruning, and equality branches', () {
      final user = _attr('user', 'alice');
      final map = IdMap()
        ..add(_id(1, 0), attributes: [user])
        ..add(_id(1, 1), attributes: [user]);
      final different = IdMap()..add(_id(1, 0), attributes: [user]);

      expect(map.isNotEmpty, isTrue);
      expect(map.slice(client: ClientId(1), range: _range(0, 0)), isEmpty);
      expect(
        map.slice(client: ClientId(9), range: _range(0, 2)).first.attributes,
        isNull,
      );
      map
        ..deleteRange(ClientId(9), _range(0, 1))
        ..deleteRange(ClientId(1), _range(0, 0))
        ..delete(_id(1, 0), length: 2);

      expect(map.isEmpty, isTrue);
      expect(map.attributes, isEmpty);
      expect(map == Object(), isFalse);
      expect(map == different, isFalse);
      expect(different.intersect(IdMap()).isEmpty, isTrue);
      expect(different.intersectIdSet(IdSet()).isEmpty, isTrue);
      expect(different.hashCode, different.hashCode);
    });

    test('covers id-map codec cached names and malformed ids', () {
      final map = IdMap()
        ..add(_id(1, 0), attributes: [_attr('user', 'alice')])
        ..add(_id(1, 1), attributes: [_attr('user', 'bob')])
        ..add(_id(1, 2), attributes: [_attr('user', 'alice')]);
      final writer = ByteWriter();
      IdMapEncoderV1.write(writer, map);

      expect(IdMapDecoderV1.read(ByteReader(writer.toBytes())), map);
      expect(IdMapDecoderV2.read(ByteReader(writer.toBytes())), map);
      expect(_idMapError([1, 1, 1, 0, 1, 1, 2]), contains('attribute id'));
      expect(
        _idMapError([1, 1, 1, 0, 1, 1, 0, 1]),
        contains('attribute name id'),
      );
    });
  });
}

Id _id(int client, int clock) =>
    Id(client: ClientId(client), clock: Clock(clock));

IdRange _range(int start, int length) {
  return IdRange(start: Clock(start), length: length);
}

ContentAttribute _attr(String name, Object? value) {
  return ContentAttribute(name, value);
}

String _idMapError(List<int> bytes) {
  try {
    IdMapDecoderV1.read(ByteReader(bytes));
  } on MalformedIdMapException catch (error) {
    expect(error.source, isNull);
    return error.message;
  }
  fail('Expected malformed id-map input.');
}
