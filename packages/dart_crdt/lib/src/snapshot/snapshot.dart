/// Snapshot value object and binary codecs.
library;

import 'dart:collection';
import 'dart:typed_data';

import '../binary/byte_reader.dart';
import '../binary/byte_writer.dart';
import '../doc/doc.dart';
import '../metadata/id_set.dart';
import '../metadata/id_set_codec.dart';
import '../structs/id.dart';
import '../structs/struct_store.dart';
import '../sync/apply_update.dart';
import '../sync/state_update.dart';
import '../sync/state_vector.dart';
import '../sync/update_inspection.dart';

part 'snapshot_restore.dart';

/// Thrown when encoded snapshot bytes are malformed.
final class MalformedSnapshotException implements FormatException {
  /// Creates an exception for malformed snapshot input.
  const MalformedSnapshotException({
    required this.offset,
    required this.reason,
    this.source,
  });

  @override
  final int offset;

  /// The reason decoding failed.
  final String reason;

  @override
  final Object? source;

  @override
  String get message => 'Malformed snapshot at offset $offset: $reason.';

  @override
  String toString() => 'MalformedSnapshotException: $message';
}

/// Delete-set and state-vector pair describing a document version.
final class Snapshot {
  /// Creates an immutable snapshot from [deleteSet] and [stateVector].
  ///
  /// Example:
  /// ```dart
  /// final snap = Snapshot(deleteSet: IdSet(), stateVector: const {});
  /// final bytes = encodeSnapshot(snap);
  /// final decoded = decodeSnapshot(bytes);
  /// ```
  Snapshot({
    IdSet? deleteSet,
    StateVector stateVector = const {},
  })  : _deleteSet = _copyIdSet(deleteSet ?? IdSet()),
        _stateVector = _copyStateVector(stateVector);

  final IdSet _deleteSet;
  final StateVector _stateVector;

  /// Deleted ids visible at this snapshot.
  IdSet get deleteSet => _copyIdSet(_deleteSet);

  /// Exclusive end clocks visible at this snapshot.
  StateVector get stateVector => _copyStateVector(_stateVector);

  /// Whether no state or delete ranges are recorded.
  bool get isEmpty => _deleteSet.isEmpty && _stateVector.isEmpty;

  @override
  bool operator ==(Object other) {
    return other is Snapshot &&
        _deleteSet == other._deleteSet &&
        _stateVectorsEqual(_stateVector, other._stateVector);
  }

  @override
  int get hashCode {
    return Object.hash(
      _deleteSet,
      Object.hashAll(
        _stateVector.entries.map(
          (entry) => Object.hash(entry.key, entry.value),
        ),
      ),
    );
  }

  @override
  String toString() {
    return 'Snapshot(deleteSet: $_deleteSet, stateVector: $_stateVector)';
  }
}

/// Creates a snapshot from [deleteSet] and [stateVector].
///
/// Example:
/// ```dart
/// final snap = createSnapshot(IdSet(), const {});
/// ```
Snapshot createSnapshot(IdSet deleteSet, StateVector stateVector) {
  return Snapshot(deleteSet: deleteSet, stateVector: stateVector);
}

/// Creates a snapshot of [document]'s current store state.
///
/// Example:
/// ```dart
/// final doc = Doc();
/// final snap = snapshot(doc);
/// ```
Snapshot snapshot(Doc document) {
  return createSnapshot(
    createDeleteSetFromStore(document.store),
    documentStateVector(document),
  );
}

/// Returns a new empty snapshot.
///
/// Example:
/// ```dart
/// final snap = emptySnapshot;
/// ```
Snapshot get emptySnapshot => Snapshot();

/// Encodes [snapshot] with the V1 snapshot codec.
///
/// Example:
/// ```dart
/// final bytes = encodeSnapshot(emptySnapshot);
/// ```
Uint8List encodeSnapshot(Snapshot snapshot) {
  final writer = ByteWriter();
  IdSetEncoderV1.write(writer, snapshot._deleteSet);
  writeStateVector(writer, snapshot._stateVector);
  return writer.toBytes();
}

/// Encodes [snapshot] with the V2 snapshot codec.
Uint8List encodeSnapshotV2(Snapshot snapshot) {
  final writer = ByteWriter();
  IdSetEncoderV2.write(writer, snapshot._deleteSet);
  writeStateVector(writer, snapshot._stateVector);
  return writer.toBytes();
}

/// Decodes a complete V1 snapshot payload.
///
/// Example:
/// ```dart
/// final snap = decodeSnapshot(encodeSnapshot(emptySnapshot));
/// ```
Snapshot decodeSnapshot(List<int> bytes) {
  final reader = ByteReader(bytes);
  final deleteSet = IdSetDecoderV1.read(reader);
  final state = readStateVector(reader);
  _requireDone(reader, bytes);
  return Snapshot(deleteSet: deleteSet, stateVector: state);
}

/// Decodes a complete V2 snapshot payload.
Snapshot decodeSnapshotV2(List<int> bytes) {
  final reader = ByteReader(bytes);
  final deleteSet = IdSetDecoderV2.read(reader);
  final state = readStateVector(reader);
  _requireDone(reader, bytes);
  return Snapshot(deleteSet: deleteSet, stateVector: state);
}

void _requireDone(ByteReader reader, List<int> bytes) {
  if (reader.isDone) {
    return;
  }
  throw MalformedSnapshotException(
    offset: reader.offset,
    reason: '${reader.remaining} trailing byte(s)',
    source: bytes,
  );
}

IdSet _copyIdSet(IdSet source) {
  final copy = IdSet();
  source.insertInto(copy);
  return copy;
}

StateVector _copyStateVector(StateVector source) {
  final state = SplayTreeMap<ClientId, Clock>(
    (left, right) => left.compareTo(right),
  )..addAll(source);
  return Map<ClientId, Clock>.unmodifiable(state);
}

bool _stateVectorsEqual(StateVector left, StateVector right) {
  if (left.length != right.length) {
    return false;
  }
  for (final entry in left.entries) {
    if (right[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}
