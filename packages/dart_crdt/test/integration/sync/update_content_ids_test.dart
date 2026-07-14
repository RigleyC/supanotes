import 'dart:convert';
import 'dart:io';

import 'package:dart_crdt/src/content/content.dart';
import 'package:dart_crdt/src/doc/doc.dart';
import 'package:dart_crdt/src/metadata/content_ids.dart';
import 'package:dart_crdt/src/metadata/id_range.dart';
import 'package:dart_crdt/src/metadata/id_set.dart';
import 'package:dart_crdt/src/structs/abstract_struct.dart';
import 'package:dart_crdt/src/structs/id.dart';
import 'package:dart_crdt/src/sync/apply_update.dart';
import 'package:dart_crdt/src/sync/state_update.dart';
import 'package:dart_crdt/src/sync/update_content_ids.dart';
import 'package:test/test.dart' hide Skip;

void main() {
  group('createContentIdsFromUpdate', () {
    test('extracts insert-only and delete-only V1 content ids', () {
      final insertUpdate = encodeStateAsUpdate(_docWithItem('abc'));
      final deleteDoc = Doc()
        ..store.addPendingDeleteSet(IdSet()..add(_id(1, 1), length: 2));

      expect(
        createContentIdsFromUpdate(insertUpdate),
        ContentIds(inserts: _set([(1, 0, 3)])),
      );
      expect(
        createContentIdsFromUpdate(encodeStateAsUpdate(deleteDoc)),
        ContentIds(deletes: _set([(1, 1, 2)])),
      );
    });

    test('extracts V2 ids with parity to V1', () {
      final doc = _docWithItem('v2');

      expect(
        createContentIdsFromUpdateV2(encodeStateAsUpdateV2(doc)),
        createContentIdsFromUpdate(encodeStateAsUpdate(doc)),
      );
    });
  });

  group('intersectUpdateWithContentIds', () {
    test('returns empty intersections for unselected ids', () {
      final update = encodeStateAsUpdate(_docWithItem('abc'));

      expect(
        createContentIdsFromUpdate(
          intersectUpdateWithContentIds(
            update,
            ContentIds(inserts: _set([(2, 0, 1)])),
          ),
        ).isEmpty,
        isTrue,
      );
    });

    test('slices overlapping insert content ids', () {
      final update = encodeStateAsUpdate(_docWithItem('abcd'));
      final filtered = intersectUpdateWithContentIds(
        update,
        ContentIds(inserts: _set([(1, 1, 2)])),
      );

      expect(
        createContentIdsFromUpdate(filtered),
        ContentIds(inserts: _set([(1, 1, 2)])),
      );

      final target = Doc();
      applyUpdate(target, filtered);
      expect(_text(target), 'bc');
    });

    test('filters delete sets independently from inserts', () {
      final doc = _docWithItem('abc')
        ..store.addPendingDeleteSet(IdSet()..add(_id(1, 1), length: 2));
      final filtered = intersectUpdateWithContentIds(
        encodeStateAsUpdate(doc),
        ContentIds(deletes: _set([(1, 2, 1)])),
      );

      expect(
        createContentIdsFromUpdate(filtered),
        ContentIds(deletes: _set([(1, 2, 1)])),
      );
    });

    test('keeps V1 and V2 intersection parity', () {
      final doc = _docWithItem('abcd');
      final ids = ContentIds(inserts: _set([(1, 0, 2)]));
      final v1 = intersectUpdateWithContentIds(encodeStateAsUpdate(doc), ids);
      final v2 =
          intersectUpdateWithContentIdsV2(encodeStateAsUpdateV2(doc), ids);

      expect(createContentIdsFromUpdate(v1), ids);
      expect(createContentIdsFromUpdateV2(v2), ids);
    });

    test('uses fixture cases for attribution and undo integrations', () {
      final fixture = _loadFixture();
      final doc = _docWithItem('ab')
        ..store.addPendingDeleteSet(IdSet()..add(_id(1, 0)));
      final attributionIds = _contentIdsFromFixture(fixture['attribution']);
      final undoIds = _contentIdsFromFixture(fixture['undo']);

      expect(
        createContentIdsFromUpdate(
          intersectUpdateWithContentIds(
            encodeStateAsUpdate(doc),
            attributionIds,
          ),
        ),
        attributionIds,
      );
      expect(
        createContentIdsFromUpdate(
          intersectUpdateWithContentIds(encodeStateAsUpdate(doc), undoIds),
        ),
        undoIds,
      );
    });
  });
}

Doc _docWithItem(String text) {
  final doc = Doc(clientId: ClientId(1));
  doc.store.add(
    Item(
      id: _id(1, 0),
      parent: doc.itemParentForKey('root'),
      content: ContentString(text),
    ),
  );
  return doc;
}

Map<String, Object?> _loadFixture() {
  final file = File(
    'test/fixtures/compat/update_content_ids/attribution_undo_cases.json',
  );
  final decoded = jsonDecode(file.readAsStringSync());
  if (decoded is! Map<String, Object?>) {
    throw StateError('Expected fixture object.');
  }
  return decoded;
}

ContentIds _contentIdsFromFixture(Object? value) {
  final data = value as Map<String, Object?>;
  return ContentIds(
    inserts: _idSetFromFixture(data['inserts']),
    deletes: _idSetFromFixture(data['deletes']),
  );
}

IdSet _idSetFromFixture(Object? value) {
  final set = IdSet();
  for (final entry in value! as List<Object?>) {
    final data = entry! as Map<String, Object?>;
    set.addRange(
      ClientId(data['client']! as int),
      _range(data['start']! as int, data['length']! as int),
    );
  }
  return set;
}

IdSet _set(List<(int client, int start, int length)> ranges) {
  final set = IdSet();
  for (final range in ranges) {
    set.addRange(ClientId(range.$1), _range(range.$2, range.$3));
  }
  return set;
}

Id _id(int client, int clock) {
  return Id(client: ClientId(client), clock: Clock(clock));
}

IdRange _range(int start, int length) {
  return IdRange(start: Clock(start), length: length);
}

String _text(Doc doc) {
  return [
    for (final item in doc.itemParentForKey('root').items())
      if (!item.deleted && item.content is ContentString)
        (item.content as ContentString).value,
  ].join();
}
