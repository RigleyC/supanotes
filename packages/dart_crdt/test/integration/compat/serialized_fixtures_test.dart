import 'dart:convert';
import 'dart:io';

import 'package:dart_crdt/src/binary/byte_reader.dart';
import 'package:dart_crdt/src/binary/byte_writer.dart';
import 'package:dart_crdt/src/doc/doc.dart';
import 'package:dart_crdt/src/metadata/content_metadata_codec.dart';
import 'package:dart_crdt/src/metadata/id_map.dart';
import 'package:dart_crdt/src/metadata/id_map_codec.dart';
import 'package:dart_crdt/src/relative_position/relative_position.dart';
import 'package:dart_crdt/src/snapshot/snapshot.dart';
import 'package:dart_crdt/src/structs/abstract_struct.dart';
import 'package:dart_crdt/src/structs/id.dart';
import 'package:dart_crdt/src/sync/apply_update.dart';
import 'package:dart_crdt/src/sync/state_update.dart';
import 'package:dart_crdt/src/sync/state_vector.dart';
import 'package:test/test.dart';

part 'serialized_fixtures_helpers.dart';

const _fixturePath = 'test/fixtures/compat/cases.jsonl';
const _directions = ['reference-to-dart', 'dart-to-reference'];

void main() {
  test('serialized fixtures apply and regenerate supported payloads exactly',
      () {
    final cases = _fixtureCases();

    expect(cases, hasLength(15));
    for (final fixtureCase in cases) {
      final expected = _mapField(fixtureCase, 'expected');

      _expectUpdateFixture(fixtureCase, expected, 'update-v1');
      _expectUpdateFixture(fixtureCase, expected, 'update-v2');
      _expectStateVectorFixture(fixtureCase, expected);
      _expectIdMapFixture(fixtureCase, expected);
      _expectContentMapFixture(fixtureCase, expected);
      _expectSnapshotFixture(fixtureCase, expected);
      _expectRelativePositionFixture(fixtureCase, expected);
    }
  });
}

void _expectUpdateFixture(
  Map<String, Object?> fixtureCase,
  Map<String, Object?> expected,
  String format,
) {
  for (final direction in _directions) {
    final payload = _payload(fixtureCase, direction, format);
    final doc = Doc(gc: false);

    if (format == 'update-v1') {
      applyUpdate(doc, payload);
    } else {
      applyUpdateV2(doc, payload);
    }

    expect(
      _jsonState(documentStateVector(doc)),
      _intMap(expected, 'appliedStateVector'),
    );
    expect(_contentRefs(doc), _intList(expected, 'contentRefs'));
    expect(_deletedCount(doc), expected['deletedCount']);
    expect(doc.store.pendingStructs.isNotEmpty, expected['pendingStructs']);
    expect(doc.store.pendingDeleteSet.isNotEmpty, expected['pendingDeletes']);
    expect(
      _sortedStrings(doc.getSubdocGuids()),
      _stringList(expected, 'subdocGuids'),
    );

    final regenerated = format == 'update-v1'
        ? encodeStateAsUpdate(doc)
        : encodeStateAsUpdateV2(doc);
    expect(
      _hex(regenerated),
      _hex(payload),
      reason: '${fixtureCase['id']} $format',
    );
  }
}

void _expectStateVectorFixture(
  Map<String, Object?> fixtureCase,
  Map<String, Object?> expected,
) {
  for (final direction in _directions) {
    final payload = _payload(fixtureCase, direction, 'state-vector');
    final state = decodeStateVector(payload);

    expect(_jsonState(state), _intMap(expected, 'stateVector'));
    expect(_hex(encodeStateVector(state)), _hex(payload));
  }
}

void _expectIdMapFixture(
  Map<String, Object?> fixtureCase,
  Map<String, Object?> expected,
) {
  for (final direction in _directions) {
    final payload = _payload(fixtureCase, direction, 'id-map');
    final reader = ByteReader(payload);
    final map = IdMapDecoderV2.read(reader);

    expect(reader.isDone, isTrue);
    expect(_clients(map.clients), _intList(expected, 'idMapClients'));
    expect(_hex(_encodeIdMap(map)), _hex(payload));
  }
}

void _expectContentMapFixture(
  Map<String, Object?> fixtureCase,
  Map<String, Object?> expected,
) {
  for (final direction in _directions) {
    final payload = _payload(fixtureCase, direction, 'content-map');
    final reader = ByteReader(payload);
    final map = readContentMap(reader);

    expect(reader.isDone, isTrue);
    expect(
      _clients(map.inserts.clients),
      _intList(expected, 'contentMapInsertClients'),
    );
    expect(
      _clients(map.deletes.clients),
      _intList(expected, 'contentMapDeleteClients'),
    );
    expect(_hex(encodeContentMap(map)), _hex(payload));
  }
}

void _expectRelativePositionFixture(
  Map<String, Object?> fixtureCase,
  Map<String, Object?> expected,
) {
  for (final direction in _directions) {
    final payload = _payload(fixtureCase, direction, 'relative-position');
    final position = decodeRelativePosition(payload);

    expect(position.toJson(), _mapField(expected, 'relativePosition'));
    expect(_hex(encodeRelativePosition(position)), _hex(payload));
  }
}

void _expectSnapshotFixture(
  Map<String, Object?> fixtureCase,
  Map<String, Object?> expected,
) {
  for (final direction in _directions) {
    final payload = _payload(fixtureCase, direction, 'snapshot');
    final snapshot = decodeSnapshot(payload);

    expect(
      _jsonState(snapshot.stateVector),
      _mapField(expected, 'snapshotStateVector'),
    );
    expect(
      _clients(snapshot.deleteSet.clients),
      _intList(expected, 'snapshotDeleteClients'),
    );
    expect(_hex(encodeSnapshot(snapshot)), _hex(payload));
  }
}
