import 'dart:typed_data';

import 'package:dart_crdt/src/binary/any_value.dart';
import 'package:dart_crdt/src/metadata/attr_range.dart';
import 'package:dart_crdt/src/metadata/attr_ranges.dart';
import 'package:dart_crdt/src/metadata/content_attribute.dart';
import 'package:dart_crdt/src/metadata/content_ids.dart';
import 'package:dart_crdt/src/metadata/content_map.dart';
import 'package:dart_crdt/src/metadata/id_map.dart';
import 'package:dart_crdt/src/metadata/id_range.dart';
import 'package:dart_crdt/src/metadata/id_ranges.dart';
import 'package:dart_crdt/src/metadata/id_set.dart';
import 'package:dart_crdt/src/structs/id.dart';
import 'package:test/test.dart';

void main() {
  group('metadata supplemental coverage', () {
    test('covers attribute value keys and equality helpers', () {
      final attrs = [
        ContentAttribute('null', null),
        ContentAttribute('bool', false),
        ContentAttribute('zero', 0.0),
        ContentAttribute('whole', 2.0),
        ContentAttribute('fraction', 2.5),
        ContentAttribute('string', 'x'),
        ContentAttribute.fromAny(
          name: 'json-list',
          value: JsonList([const JsonString('x')]),
        ),
        ContentAttribute.fromAny(
          name: 'json-map',
          value: JsonMap({'b': const JsonBool(true)}),
        ),
        ContentAttribute.fromAny(
          name: 'any-list',
          value: AnyList([
            AnyBinary(Uint8List.fromList([1])),
          ]),
        ),
        ContentAttribute.fromAny(
          name: 'any-map',
          value: AnyMap({'k': JsonNumber(3)}),
        ),
      ];

      expect(attrs.map((attr) => attr.stableHash).toSet(), hasLength(10));
      expect(attrs.first.toJson(), {'name': 'null', 'value': null});
      expect(attrs.first.toString(), 'null=null');
      expect(contentAttributesEqual(attrs, attrs.take(9).toList()), isFalse);
      expect(
        contentAttributesEqual([attrs.first], [ContentAttribute('null', true)]),
        isFalse,
      );
    });

    test('covers AttrRange and MaybeAttrRange branch behavior', () {
      final alice = _attr('user', 'Alice');
      final range = _attrRange(2, 3, [alice]);
      final copied = range.copyWith(start: Clock(1), length: 2);
      final unchangedCopy = range.copyWith();
      final withMore = range.withAttributes([_attr('reviewer', 'Bob')]);
      final empty = const MaybeAttrRange.empty();
      final emptyPresent = MaybeAttrRange.present(_attrRange(0, 0, [alice]));
      final emptyGap = MaybeAttrRange.gap(start: Clock(0), length: 0);
      final gap = MaybeAttrRange.gap(start: Clock(5), length: 1);

      expect(copied.idRange, _range(1, 2));
      expect(unchangedCopy, range);
      expect(withMore.attributes, [_attr('reviewer', 'Bob'), alice]);
      expect(range.intersect(_range(3, 1)).idRange, _range(3, 1));
      expect(range.intersect(_range(8, 1)), empty);
      expect(range.compareTo(_attrRange(3, 1, [alice])), isNegative);
      expect(
        range.compareTo(_attrRange(2, 3, [alice, _attr('extra', true)])),
        isNegative,
      );
      expect(range.hashCode, _attrRange(2, 3, [alice]).hashCode);
      expect(range.toString(), contains('@'));
      expect(empty.isEmpty, isTrue);
      expect(MaybeAttrRange.present(range).isPresent, isTrue);
      expect(gap.isGap, isTrue);
      expect(emptyPresent, empty);
      expect(emptyGap, empty);
      expect(() => empty.idRange, throwsStateError);
      expect(gap.toString(), 'gap:${_range(5, 1)}');
      expect(empty.toString(), 'empty');
    });

    test('covers AttrRanges empty, slice, diff, intersection, and filters', () {
      final alice = _attr('user', 'Alice');
      final bob = _attr('reviewer', 'Bob');
      final ranges = AttrRanges([
        _attrRange(1, 2, [alice]),
        _attrRange(4, 2, [bob]),
      ]);
      final other = AttrRanges([
        _attrRange(2, 3, [bob]),
      ]);
      final visited = <AttrRange>[];

      ranges.forEach(visited.add);

      expect(AttrRanges.empty.isNotEmpty, isFalse);
      expect(AttrRanges.empty.add(_attrRange(0, 0, [alice])), AttrRanges.empty);
      expect(ranges.has(Clock(0)), isFalse);
      expect(ranges.has(Clock(1)), isTrue);
      expect(ranges.delete(_range(0, 0)), same(ranges));
      expect(AttrRanges.empty.delete(_range(0, 1)), AttrRanges.empty);
      expect(ranges.slice(_range(0, 0)), isEmpty);
      expect(ranges.slice(_range(0, 7)), [
        MaybeAttrRange.gap(start: Clock(0), length: 1),
        MaybeAttrRange.present(_attrRange(1, 2, [alice])),
        MaybeAttrRange.gap(start: Clock(3), length: 1),
        MaybeAttrRange.present(_attrRange(4, 2, [bob])),
        MaybeAttrRange.gap(start: Clock(6), length: 1),
      ]);
      expect(AttrRanges.empty.merged(ranges), ranges);
      expect(ranges.merged(AttrRanges.empty), ranges);
      expect(
        ranges.diffIdRanges(IdRanges([_range(1, 10)])),
        AttrRanges.empty,
      );
      expect(ranges.diff(other).ranges, [
        _attrRange(1, 1, [alice]),
        _attrRange(5, 1, [bob]),
      ]);
      expect(ranges.intersect(other).ranges, [
        _attrRange(2, 1, [alice, bob]),
        _attrRange(4, 1, [bob]),
      ]);
      expect(
        ranges.intersectIdRanges(IdRanges([_range(4, 1)])).ranges,
        [
          _attrRange(4, 1, [bob]),
        ],
      );
      expect(ranges.filter((attrs) => attrs.contains(bob)).ranges, [
        _attrRange(4, 2, [bob]),
      ]);
      expect(visited, ranges.ranges);
      expect(
        ranges ==
            AttrRanges([
              _attrRange(1, 2, [alice]),
            ]),
        isFalse,
      );
      expect(ranges.toString(), contains('user=Alice'));
    });

    test('covers ContentMap algebra, filtering, equality, and defensive copies',
        () {
      final alice = _attr('user', 'Alice');
      final bob = _attr('reviewer', 'Bob');
      final contentIds = ContentIds(
        inserts: IdSet()..add(_id(1, 0), length: 2),
        deletes: IdSet()..add(_id(2, 0)),
      );
      final left = ContentMap.fromContentIds(
        contentIds,
        insertAttributes: [alice],
        deleteAttributes: [bob],
      );
      final right = ContentMap(
        inserts: IdMap()..add(_id(1, 1), attributes: [bob]),
        deletes: IdMap()..add(_id(3, 0), attributes: [bob]),
      );

      expect(ContentMap.empty().isEmpty, isTrue);
      expect(left.isNotEmpty, isTrue);
      expect(left.inserts.hasId(_id(1, 0)), isTrue);
      expect(left.deletes.hasId(_id(2, 0)), isTrue);
      expect(left.toContentIds(), contentIds);
      expect(left.merged(right).inserts.hasId(_id(1, 1)), isTrue);
      expect(left.exclude(right).inserts.hasId(_id(1, 1)), isFalse);
      expect(
        left.excludeIds(right.toContentIds()).inserts.hasId(_id(1, 1)),
        isFalse,
      );
      expect(left.intersect(right).inserts.hasId(_id(1, 1)), isTrue);
      expect(
        left.intersectIds(right.toContentIds()).inserts.hasId(_id(1, 1)),
        isTrue,
      );
      expect(
        left.filter(
          insertPredicate: (attrs) => attrs.contains(alice),
          deletePredicate: (attrs) => attrs.contains(bob),
        ),
        left,
      );
      expect(mergeContentMaps([left, right]), left.merged(right));
      expect(
        left.hashCode,
        ContentMap(inserts: left.inserts, deletes: left.deletes).hashCode,
      );
    });
  });
}

ContentAttribute _attr(String name, Object? value) =>
    ContentAttribute(name, value);

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
