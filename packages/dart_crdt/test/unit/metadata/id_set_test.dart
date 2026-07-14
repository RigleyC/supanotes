import 'dart:convert';
import 'dart:io';

import 'package:dart_crdt/src/binary/byte_reader.dart';
import 'package:dart_crdt/src/binary/byte_writer.dart';
import 'package:dart_crdt/src/metadata/id_range.dart';
import 'package:dart_crdt/src/metadata/id_ranges.dart';
import 'package:dart_crdt/src/metadata/id_set.dart';
import 'package:dart_crdt/src/metadata/id_set_codec.dart';
import 'package:dart_crdt/src/structs/id.dart';
import 'package:test/test.dart';

void main() {
  group('IdRange', () {
    test('validates bounds and optional intersections', () {
      final range = _range(2, 5);

      expect(range.has(Clock(2)), isTrue);
      expect(range.has(Clock(6)), isTrue);
      expect(range.has(Clock(7)), isFalse);
      expect(range.intersect(_range(4, 5)).range, _range(4, 3));
      expect(range.intersect(_range(8, 1)).isEmpty, isTrue);
      expect(() => range.intersect(_range(8, 1)).range, throwsStateError);
      expect(() => IdRange(start: Clock(1), length: -1), throwsRangeError);
    });

    test('merges touching ranges and deletes middle slices', () {
      final merged = _range(2, 3).merge(_range(5, 2));

      expect(merged.range, _range(2, 5));
      expect(_range(2, 5).delete(_range(4, 1)), [
        _range(2, 2),
        _range(5, 2),
      ]);
      expect(_range(0, 0).delete(_range(0, 1)), isEmpty);
    });
  });

  group('IdRanges', () {
    test('normalizes sorted ranges and handles deletion', () {
      final ranges = IdRanges([
        _range(5, 2),
        _range(1, 3),
        _range(3, 2),
        _range(0, 0),
      ]);

      expect(ranges.ranges, [_range(1, 6)]);
      expect(ranges.delete(_range(3, 2)).ranges, [
        _range(1, 2),
        _range(5, 2),
      ]);
      expect(ranges.has(Clock(4)), isTrue);
      expect(ranges.has(Clock(7)), isFalse);
    });

    test('diffs, intersects, and slices range lists', () {
      final left = IdRanges([_range(0, 5), _range(8, 3)]);
      final right = IdRanges([_range(2, 8)]);

      expect(left.diff(right).ranges, [_range(0, 2), _range(10, 1)]);
      expect(left.intersect(right).ranges, [_range(2, 3), _range(8, 2)]);
      expect(left.slice(_range(4, 5)).ranges, [_range(4, 1), _range(8, 1)]);
    });
  });

  group('IdSet', () {
    test('adds, deletes, checks ids, slices, and iterates in order', () {
      final set = IdSet()
        ..add(_id(2, 5), length: 2)
        ..add(_id(1, 0))
        ..addRange(ClientId(2), _range(7, 2))
        ..delete(_id(2, 6), length: 2);
      final visited = <String>[];

      set.forEach(
        (client, range) =>
            visited.add('${client.value}:${range.start.value}-${range.length}'),
      );

      expect(set.hasId(_id(1, 0)), isTrue);
      expect(set.has(client: ClientId(2), clock: Clock(6)), isFalse);
      expect(
        set.slice(client: ClientId(2), range: _range(5, 3)),
        _single(2, 5),
      );
      expect(visited, ['1:0-1', '2:5-1', '2:8-1']);
      expect(() => set.clients.add(ClientId(3)), throwsUnsupportedError);
    });

    test('merges, diffs, intersects, and inserts fixture-backed sets', () {
      final fixture = _loadFixture();
      final base = _setFromFixture(fixture, 'base');
      final other = _setFromFixture(fixture, 'other');
      final target = _single(1, 10);

      base.insertInto(target);

      expect(base.merged(other), _fixtureMerged());
      expect(base.diff(other), _fixtureDiff());
      expect(base.intersect(other), _fixtureIntersect());
      expect(target.hasId(_id(1, 10)), isTrue);
      expect(target.hasId(_id(2, 4)), isTrue);
    });

    test('keeps diff and intersect partition properties for random fixtures',
        () {
      final fixture = _loadFixture();
      final left = _setFromFixture(fixture, 'randomLeft');
      final right = _setFromFixture(fixture, 'randomRight');
      final diff = left.diff(right);
      final overlap = left.intersect(right);

      expect(diff.intersect(right).isEmpty, isTrue);
      expect(overlap.diff(right).isEmpty, isTrue);
      expect(diff.merged(overlap), left);
    });

    test('ignores zero-length mutations and round-trips binary codecs', () {
      final set = _fixtureMerged()
        ..add(_id(9, 9), length: 0)
        ..delete(_id(1, 0), length: 0);

      expect(_roundTripV1(set), set);
      expect(_roundTripV2(set), set);
      expect(_roundTripV1(IdSet()), IdSet());
      expect(IdSetEncoderV1, isNotNull);
      expect(IdSetEncoderV2, isNotNull);
    });
  });
}

Id _id(int client, int clock) {
  return Id(client: ClientId(client), clock: Clock(clock));
}

IdRange _range(int start, int length) {
  return IdRange(start: Clock(start), length: length);
}

IdSet _single(int client, int clock) {
  return IdSet()..add(_id(client, clock));
}

IdSet _fixtureMerged() {
  return IdSet.fromRanges({
    ClientId(1): [_range(0, 7)],
    ClientId(2): [_range(1, 4)],
    ClientId(3): [_range(0, 2)],
  });
}

IdSet _fixtureDiff() {
  return IdSet.fromRanges({
    ClientId(1): [_range(0, 2), _range(6, 1)],
    ClientId(2): [_range(1, 2), _range(4, 1)],
  });
}

IdSet _fixtureIntersect() {
  return IdSet.fromRanges({
    ClientId(1): [_range(2, 1), _range(5, 1)],
    ClientId(2): [_range(3, 1)],
  });
}

Map<String, Object?> _loadFixture() {
  final content = File(
    'test/fixtures/metadata/id_set_ranges.json',
  ).readAsStringSync();
  final decoded = jsonDecode(content);
  if (decoded is! Map<String, Object?>) {
    throw StateError('Expected metadata fixture object.');
  }
  return decoded;
}

IdSet _setFromFixture(Map<String, Object?> fixture, String key) {
  final entries = fixture[key];
  if (entries is! List<Object?>) {
    throw StateError('Expected fixture list for $key.');
  }

  final set = IdSet();
  for (final entry in entries) {
    if (entry is! Map<String, Object?>) {
      throw StateError('Expected fixture entry object.');
    }
    set.addRange(
      ClientId(entry['client']! as int),
      _range(entry['start']! as int, entry['length']! as int),
    );
  }
  return set;
}

IdSet _roundTripV1(IdSet set) {
  final writer = ByteWriter();
  IdSetEncoderV1.write(writer, set);
  return IdSetDecoderV1.read(ByteReader(writer.toBytes()));
}

IdSet _roundTripV2(IdSet set) {
  final writer = ByteWriter();
  IdSetEncoderV2.write(writer, set);
  return IdSetDecoderV2.read(ByteReader(writer.toBytes()));
}
