import 'dart:convert';
import 'dart:io';

import 'package:dart_crdt/src/binary/byte_reader.dart';
import 'package:dart_crdt/src/binary/byte_writer.dart';
import 'package:dart_crdt/src/metadata/attr_range.dart';
import 'package:dart_crdt/src/metadata/attr_ranges.dart';
import 'package:dart_crdt/src/metadata/content_attribute.dart';
import 'package:dart_crdt/src/metadata/id_map.dart';
import 'package:dart_crdt/src/metadata/id_map_codec.dart';
import 'package:dart_crdt/src/metadata/id_range.dart';
import 'package:dart_crdt/src/metadata/id_set.dart';
import 'package:dart_crdt/src/structs/id.dart';
import 'package:test/test.dart';

void main() {
  group('ContentAttribute', () {
    test('uses immutable equality and canonical stable hashing', () {
      final left = ContentAttribute('meta', {'b': 2, 'a': 1});
      final right = ContentAttribute('meta', {'a': 1, 'b': 2});
      final other = ContentAttribute('meta', {'a': 1, 'b': 3});

      expect(left, right);
      expect(left.stableHash, right.stableHash);
      expect(left, isNot(other));
      expect(normalizeContentAttributes([other, left, right]), [left, other]);
    });
  });

  group('AttrRanges', () {
    test('splits overlapping ranges and merges equal neighbors', () {
      final alice = _attr('user', 'Alice');
      final bob = _attr('reviewer', 'Bob');
      final ranges = AttrRanges([
        _attrRange(1, 2, [alice]),
        _attrRange(0, 2, [bob]),
        _attrRange(3, 1, [alice]),
      ]);

      expect(ranges.ranges, [
        _attrRange(0, 1, [bob]),
        _attrRange(1, 1, [alice, bob]),
        _attrRange(2, 2, [alice]),
      ]);
      expect(ranges.delete(_range(1, 2)).ranges, [
        _attrRange(0, 1, [bob]),
        _attrRange(3, 1, [alice]),
      ]);
    });
  });

  group('IdMap', () {
    test('adds, deletes, checks ids, slices gaps, and filters ranges', () {
      final alice = _attr('user', 'Alice');
      final bob = _attr('reviewer', 'Bob');
      final map = IdMap()
        ..add(_id(1, 1), length: 3, attributes: [alice])
        ..add(_id(1, 2), length: 2, attributes: [bob])
        ..delete(_id(1, 3));

      expect(map.hasId(_id(1, 1)), isTrue);
      expect(map.has(client: ClientId(1), clock: Clock(3)), isFalse);
      expect(map.sliceId(_id(1, 0), length: 5), [
        MaybeAttrRange.gap(start: Clock(0), length: 1),
        MaybeAttrRange.present(_attrRange(1, 1, [alice])),
        MaybeAttrRange.present(_attrRange(2, 1, [alice, bob])),
        MaybeAttrRange.gap(start: Clock(3), length: 2),
      ]);
      expect(
        map.filter((attrs) => attrs.contains(bob)).rangesFor(ClientId(1)),
        [
          _attrRange(2, 1, [alice, bob]),
        ],
      );
      expect(() => map.attributes.add(alice), throwsUnsupportedError);
    });

    test('merges, diffs, intersects, and converts fixture-backed maps', () {
      final fixture = _loadFixture();
      final base = _mapFromFixture(fixture, 'base');
      final other = _mapFromFixture(fixture, 'other');

      expect(base.merged(other), _expectedMerged());
      expect(base.diff(other), _expectedDiff());
      expect(base.intersect(other), _expectedIntersect());
      expect(
        IdMap.fromIdSet(
          base.toIdSet(),
          [_attr('copy', true)],
        ).hasId(_id(2, 2)),
        isTrue,
      );
      expect(
        base.diffIdSet(_singleSet(1, 0, 1)).hasId(_id(1, 0)),
        isFalse,
      );
    });

    test('round-trips binary codecs without duplicate attr definitions', () {
      final fixture = _loadFixture();
      final repeated = _mapFromFixture(fixture, 'repeated');
      final merged = _expectedMerged();

      expect(repeated.attributes, [_attr('user', 'Alice')]);
      expect(_roundTripV1(merged), merged);
      expect(_roundTripV2(merged), merged);
      expect(_countNeedle(_encodedV2(repeated), utf8.encode('Alice')), 1);
      expect(_roundTripV2(IdMap()), IdMap());
    });
  });
}

ContentAttribute _attr(String name, Object? value) {
  return ContentAttribute(name, value);
}

Id _id(int client, int clock) {
  return Id(client: ClientId(client), clock: Clock(clock));
}

IdRange _range(int start, int length) {
  return IdRange(start: Clock(start), length: length);
}

AttrRange _attrRange(
  int start,
  int length,
  Iterable<ContentAttribute> attrs,
) {
  return AttrRange(start: Clock(start), length: length, attributes: attrs);
}

Map<String, Object?> _loadFixture() {
  final content = File(
    'test/fixtures/metadata/id_map_ranges.json',
  ).readAsStringSync();
  final decoded = jsonDecode(content);
  if (decoded is! Map<String, Object?>) {
    throw StateError('Expected metadata fixture object.');
  }
  return decoded;
}

IdMap _mapFromFixture(Map<String, Object?> fixture, String key) {
  final entries = fixture[key];
  if (entries is! List<Object?>) {
    throw StateError('Expected fixture list for $key.');
  }

  final map = IdMap();
  for (final entry in entries) {
    if (entry is! Map<String, Object?>) {
      throw StateError('Expected fixture entry object.');
    }
    map.addRange(
      ClientId(entry['client']! as int),
      _attrRange(
        entry['start']! as int,
        entry['length']! as int,
        _attrsFromFixture(entry['attrs']),
      ),
    );
  }
  return map;
}

List<ContentAttribute> _attrsFromFixture(Object? attrs) {
  if (attrs is! List<Object?>) {
    throw StateError('Expected attrs list.');
  }
  return [
    for (final attr in attrs)
      if (attr is Map<String, Object?>)
        _attr(attr['name']! as String, attr['value']),
  ];
}

IdMap _expectedMerged() {
  return IdMap()
    ..add(_id(1, 0), length: 2, attributes: [_attr('user', 'Alice')])
    ..add(
      _id(1, 2),
      attributes: [_attr('user', 'Alice'), _attr('reviewer', 'Bob')],
    )
    ..add(_id(1, 3), length: 2, attributes: [_attr('reviewer', 'Bob')])
    ..add(_id(1, 5), length: 2, attributes: [_attr('user', 'Alice')])
    ..add(_id(2, 1), length: 2, attributes: [_attr('origin', 'local')])
    ..add(_id(3, 0), attributes: [_attr('user', 'Alice')]);
}

IdMap _expectedDiff() {
  return IdMap()
    ..add(_id(1, 0), length: 2, attributes: [_attr('user', 'Alice')])
    ..add(_id(1, 5), length: 2, attributes: [_attr('user', 'Alice')])
    ..add(_id(2, 1), length: 2, attributes: [_attr('origin', 'local')]);
}

IdMap _expectedIntersect() {
  return IdMap()
    ..add(
      _id(1, 2),
      attributes: [_attr('user', 'Alice'), _attr('reviewer', 'Bob')],
    );
}

IdSet _singleSet(int client, int start, int length) {
  return IdSet()..add(_id(client, start), length: length);
}

IdMap _roundTripV1(IdMap map) {
  final writer = ByteWriter();
  IdMapEncoderV1.write(writer, map);
  return IdMapDecoderV1.read(ByteReader(writer.toBytes()));
}

IdMap _roundTripV2(IdMap map) {
  return IdMapDecoderV2.read(ByteReader(_encodedV2(map)));
}

List<int> _encodedV2(IdMap map) {
  final writer = ByteWriter();
  IdMapEncoderV2.write(writer, map);
  return writer.toBytes();
}

int _countNeedle(List<int> haystack, List<int> needle) {
  var count = 0;
  for (var index = 0; index <= haystack.length - needle.length; index += 1) {
    if (haystack.sublist(index, index + needle.length).join(',') ==
        needle.join(',')) {
      count += 1;
    }
  }
  return count;
}
