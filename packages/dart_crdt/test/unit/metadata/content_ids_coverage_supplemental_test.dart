import 'package:dart_crdt/src/metadata/content_attribute.dart';
import 'package:dart_crdt/src/metadata/content_ids.dart';
import 'package:dart_crdt/src/metadata/content_map.dart';
import 'package:dart_crdt/src/metadata/id_map.dart';
import 'package:dart_crdt/src/metadata/id_range.dart';
import 'package:dart_crdt/src/metadata/id_set.dart';
import 'package:dart_crdt/src/structs/id.dart';
import 'package:test/test.dart';

void main() {
  group('ContentIds supplemental coverage', () {
    test('covers algebra, filtering, map conversion, and identity', () {
      final left = ContentIds(
        inserts: IdSet()..add(_id(1, 0), length: 3),
        deletes: IdSet()..add(_id(2, 0), length: 2),
      );
      final right = ContentIds(
        inserts: IdSet()..add(_id(1, 1)),
        deletes: IdSet()..add(_id(3, 0)),
      );
      final map = ContentMap(
        inserts: IdMap()..add(_id(4, 0), attributes: [_attr('source', 'map')]),
        deletes: IdMap()..add(_id(5, 0), attributes: [_attr('source', 'map')]),
      );

      expect(ContentIds.empty().isEmpty, isTrue);
      expect(left.isNotEmpty, isTrue);
      expect(left.inserts.hasId(_id(1, 0)), isTrue);
      expect(left.deletes.hasId(_id(2, 1)), isTrue);
      expect(
          left
              .toContentMap(insertAttributes: [_attr('a', true)])
              .deletes
              .attributes,
          [
            _attr('a', true),
          ]);
      expect(ContentIds.fromContentMap(map).inserts.hasId(_id(4, 0)), isTrue);
      expect(left.merged(right).deletes.hasId(_id(3, 0)), isTrue);
      expect(left.exclude(right).inserts.hasId(_id(1, 1)), isFalse);
      expect(left.intersect(right).inserts.hasId(_id(1, 1)), isTrue);
      expect(
        left.filter((branch, client, range) {
          return branch == ContentBranch.inserts &&
              client == ClientId(1) &&
              range == _range(0, 3);
        }),
        ContentIds(inserts: IdSet()..add(_id(1, 0), length: 3)),
      );
      expect(mergeContentIds([left, right]), left.merged(right));
      expect(
        left.hashCode,
        ContentIds(inserts: left.inserts, deletes: left.deletes).hashCode,
      );
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
