import 'dart:convert';
import 'dart:io';

import 'package:dart_crdt/src/binary/byte_reader.dart';
import 'package:dart_crdt/src/binary/byte_writer.dart';
import 'package:dart_crdt/src/metadata/attr_range.dart';
import 'package:dart_crdt/src/metadata/content_attribute.dart';
import 'package:dart_crdt/src/metadata/content_ids.dart';
import 'package:dart_crdt/src/metadata/content_map.dart';
import 'package:dart_crdt/src/metadata/content_metadata_codec.dart';
import 'package:dart_crdt/src/metadata/id_map.dart';
import 'package:dart_crdt/src/metadata/id_range.dart';
import 'package:dart_crdt/src/metadata/id_set.dart';
import 'package:dart_crdt/src/structs/id.dart';
import 'package:test/test.dart';

void main() {
  group('ContentIds', () {
    test('supports empty content and defensive id-set copies', () {
      final content = ContentIds.empty();
      final inserts = content.inserts;

      inserts.add(_id(1, 0));

      expect(content.isEmpty, isTrue);
      expect(content.inserts.isEmpty, isTrue);
      expect(content, decodeContentIds(encodeContentIds(content)));
    });

    test('merges, excludes, intersects, filters, and converts to maps', () {
      final fixture = _loadFixture();
      final content = _contentIdsFromFixture(fixture['ids']);
      final other = _contentIdsFromFixture(fixture['otherIds']);
      final filtered = content.filter(
        (branch, client, range) {
          return branch == ContentBranch.inserts && client == ClientId(1);
        },
      );
      final mapped = content.toContentMap(
        insertAttributes: [_attr('insert', 'Alice')],
        deleteAttributes: [_attr('delete', 'Alice')],
      );

      expect(content.merged(other), _expectedMergedIds());
      expect(content.exclude(other), _expectedExcludedIds());
      expect(content.intersect(other), _expectedIntersectedIds());
      expect(filtered.deletes.isEmpty, isTrue);
      expect(filtered.inserts.hasId(_id(1, 2)), isTrue);
      expect(mapped.inserts.rangesFor(ClientId(1)).first.attributes, [
        _attr('insert', 'Alice'),
      ]);
      expect(ContentIds.fromContentMap(mapped), content);
    });
  });

  group('ContentMap', () {
    test('supports insert-only and delete-only creation', () {
      final ids = ContentIds(
        inserts: _set([(1, 0, 2)]),
        deletes: _set([(2, 5, 1)]),
      );
      final insertOnly = ContentMap.fromContentIds(
        ContentIds(inserts: ids.inserts),
        insertAttributes: [_attr('insert', 'Alice')],
      );
      final deleteOnly = ContentMap.fromContentIds(
        ContentIds(deletes: ids.deletes),
        deleteAttributes: [_attr('delete', 'Alice')],
      );

      expect(insertOnly.inserts.hasId(_id(1, 1)), isTrue);
      expect(insertOnly.deletes.isEmpty, isTrue);
      expect(deleteOnly.inserts.isEmpty, isTrue);
      expect(deleteOnly.deletes.hasId(_id(2, 5)), isTrue);
    });

    test('handles overlapping maps, ids, exclusion, intersection, and filters',
        () {
      final fixture = _loadFixture();
      final map = _contentMapFromFixture(fixture['map']);
      final ids = _contentIdsFromFixture(fixture['ids']);
      final userFiltered = map.filter(
        insertPredicate: (attrs) => attrs.contains(_attr('insert', 'Alice')),
        deletePredicate: (attrs) => attrs.contains(_attr('delete', 'Alice')),
      );

      expect(map.toContentIds(), _contentIdsFromMapFixture());
      expect(map.intersectIds(ids).inserts.rangesFor(ClientId(1)), [
        _attrRange(0, 1, [_attr('insert', 'Alice')]),
        _attrRange(1, 1, [_attr('insert', 'Alice'), _attr('review', 'Bob')]),
        _attrRange(2, 1, [_attr('review', 'Bob')]),
      ]);
      expect(map.excludeIds(ids).inserts.rangesFor(ClientId(1)), [
        _attrRange(3, 1, [_attr('review', 'Bob')]),
      ]);
      expect(userFiltered.deletes.hasId(_id(2, 5)), isTrue);
    });

    test('round-trips content id and map codecs', () {
      final fixture = _loadFixture();
      final ids = _contentIdsFromFixture(fixture['ids']);
      final map = _contentMapFromFixture(fixture['map']);
      final writer = ByteWriter();

      writeContentMap(writer, map);

      expect(decodeContentIdsV1(encodeContentIdsV1(ids)), ids);
      expect(decodeContentIdsV2(encodeContentIdsV2(ids)), ids);
      expect(readContentIds(ByteReader(encodeContentIds(ids))), ids);
      expect(decodeContentMapV1(encodeContentMapV1(map)), map);
      expect(decodeContentMapV2(encodeContentMapV2(map)), map);
      expect(readContentMap(ByteReader(writer.toBytes())), map);
    });
  });
}

Id _id(int client, int clock) {
  return Id(client: ClientId(client), clock: Clock(clock));
}

ContentAttribute _attr(String name, Object? value) {
  return ContentAttribute(name, value);
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

IdSet _set(List<(int client, int start, int length)> ranges) {
  final set = IdSet();
  for (final range in ranges) {
    set.addRange(ClientId(range.$1), _range(range.$2, range.$3));
  }
  return set;
}

Map<String, Object?> _loadFixture() {
  final content = File(
    'test/fixtures/metadata/content_metadata.json',
  ).readAsStringSync();
  final decoded = jsonDecode(content);
  if (decoded is! Map<String, Object?>) {
    throw StateError('Expected content metadata fixture object.');
  }
  return decoded;
}

ContentIds _contentIdsFromFixture(Object? value) {
  final data = _fixtureMap(value);
  return ContentIds(
    inserts: _idSetFromFixture(data['inserts']),
    deletes: _idSetFromFixture(data['deletes']),
  );
}

ContentMap _contentMapFromFixture(Object? value) {
  final data = _fixtureMap(value);
  return ContentMap(
    inserts: _idMapFromFixture(data['inserts']),
    deletes: _idMapFromFixture(data['deletes']),
  );
}

Map<String, Object?> _fixtureMap(Object? value) {
  if (value is! Map<String, Object?>) {
    throw StateError('Expected fixture object.');
  }
  return value;
}

IdSet _idSetFromFixture(Object? value) {
  final set = IdSet();
  for (final entry in _fixtureList(value)) {
    set.addRange(
      ClientId(entry['client']! as int),
      _range(entry['start']! as int, entry['length']! as int),
    );
  }
  return set;
}

IdMap _idMapFromFixture(Object? value) {
  final map = IdMap();
  for (final entry in _fixtureList(value)) {
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

List<Map<String, Object?>> _fixtureList(Object? value) {
  if (value is! List<Object?>) {
    throw StateError('Expected fixture list.');
  }
  return [
    for (final entry in value)
      if (entry is Map<String, Object?>) entry,
  ];
}

List<ContentAttribute> _attrsFromFixture(Object? attrs) {
  return [
    for (final attr in _fixtureList(attrs))
      _attr(attr['name']! as String, attr['value']),
  ];
}

ContentIds _expectedMergedIds() {
  return ContentIds(
    inserts: _set([(1, 0, 5), (2, 4, 2)]),
    deletes: _set([(1, 7, 2), (3, 0, 1)]),
  );
}

ContentIds _expectedExcludedIds() {
  return ContentIds(
    inserts: _set([(1, 0, 2), (2, 4, 2)]),
    deletes: _set([(1, 7, 2)]),
  );
}

ContentIds _expectedIntersectedIds() {
  return ContentIds(inserts: _set([(1, 2, 1)]));
}

ContentIds _contentIdsFromMapFixture() {
  return ContentIds(
    inserts: _set([(1, 0, 4)]),
    deletes: _set([(2, 5, 2)]),
  );
}
