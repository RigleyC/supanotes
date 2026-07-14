import 'dart:convert';
import 'dart:io';

import 'package:dart_crdt/dart_crdt.dart';
import 'package:dart_crdt/src/binary/byte_reader.dart';
import 'package:test/test.dart';

const _fixturePath = 'test/fixtures/snapshot/snapshot_codecs.json';

void main() {
  group('Snapshot codecs', () {
    test('round-trips fixture bytes for V1 and V2', () {
      for (final entry in _loadFixtures().entries) {
        final snapshot = _snapshotFromFixture(entry.value);
        final v1 = _decodeHex(_stringField(entry.value, 'v1Hex'));
        final v2 = _decodeHex(_stringField(entry.value, 'v2Hex'));

        expect(encodeSnapshot(snapshot), v1, reason: '${entry.key} V1');
        expect(encodeSnapshotV2(snapshot), v2, reason: '${entry.key} V2');
        expect(decodeSnapshot(v1), snapshot);
        expect(decodeSnapshotV2(v2), snapshot);
      }
    });

    test('creates empty snapshots and defensive copies', () {
      final deletes = IdSet()..add(_id(1, 0), length: 2);
      final state = {ClientId(1): Clock(2)};
      final snap = createSnapshot(deletes, state);

      deletes.add(_id(2, 0));
      state[ClientId(3)] = Clock(1);
      snap.deleteSet.add(_id(4, 0));

      expect(emptySnapshot.isEmpty, isTrue);
      expect(snap.deleteSet, IdSet()..add(_id(1, 0), length: 2));
      expect(snap.stateVector, {ClientId(1): Clock(2)});
      expect(snap, createSnapshot(snap.deleteSet, snap.stateVector));
      expect(
        snap.hashCode,
        createSnapshot(snap.deleteSet, snap.stateVector).hashCode,
      );
    });

    test('captures document state vectors and deleted ranges', () {
      final doc = Doc();
      doc.store
        ..add(GC(id: _id(1, 0), length: 2))
        ..add(GC(id: _id(2, 0), length: 1));

      final snap = snapshot(doc);

      expect(
        snap.stateVector,
        {ClientId(1): Clock(2), ClientId(2): Clock(1)},
      );
      expect(snap.deleteSet.hasId(_id(1, 1)), isTrue);
      expect(snap.deleteSet.hasId(_id(2, 0)), isTrue);
    });

    test('rejects malformed byte streams', () {
      expect(
        () => decodeSnapshot(const []),
        throwsA(isA<TruncatedInputException>()),
      );
      expect(
        () => decodeSnapshot(const [0, 0, 99]),
        throwsA(isA<MalformedSnapshotException>()),
      );
      expect(
        () => decodeSnapshot(const [1, 1]),
        throwsA(isA<TruncatedInputException>()),
      );
    });
  });
}

Map<String, Map<String, Object?>> _loadFixtures() {
  final decoded = jsonDecode(File(_fixturePath).readAsStringSync());
  final fixture = _objectMap(decoded, _fixturePath);
  return {
    for (final entry in fixture.entries)
      entry.key: _objectMap(entry.value, entry.key),
  };
}

Snapshot _snapshotFromFixture(Map<String, Object?> fixture) {
  return createSnapshot(
    _deleteSetFromFixture(_objectList(fixture['deleteSet'], 'deleteSet')),
    _stateVectorFromFixture(_objectMap(fixture['stateVector'], 'stateVector')),
  );
}

IdSet _deleteSetFromFixture(List<Object?> entries) {
  final set = IdSet();
  for (final entry in entries) {
    final map = _objectMap(entry, 'deleteSet entry');
    set.addRange(
      ClientId(_intField(map, 'client')),
      IdRange(
        start: Clock(_intField(map, 'start')),
        length: _intField(map, 'length'),
      ),
    );
  }
  return set;
}

StateVector _stateVectorFromFixture(Map<String, Object?> value) {
  return {
    for (final entry in value.entries)
      ClientId(int.parse(entry.key)): Clock(_intValue(entry.value, entry.key)),
  };
}

Id _id(int client, int clock) {
  return Id(client: ClientId(client), clock: Clock(clock));
}

List<int> _decodeHex(String value) {
  return [
    for (var index = 0; index < value.length; index += 2)
      int.parse(value.substring(index, index + 2), radix: 16),
  ];
}

Map<String, Object?> _objectMap(Object? value, String context) {
  if (value is Map<String, Object?>) {
    return value;
  }
  throw StateError('$context must be an object.');
}

List<Object?> _objectList(Object? value, String context) {
  if (value is List<Object?>) {
    return value;
  }
  throw StateError('$context must be a list.');
}

String _stringField(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is String) {
    return field;
  }
  throw StateError('$key must be a string.');
}

int _intField(Map<String, Object?> value, String key) {
  return _intValue(value[key], key);
}

int _intValue(Object? value, String key) {
  if (value is int) {
    return value;
  }
  throw StateError('$key must be an int.');
}
