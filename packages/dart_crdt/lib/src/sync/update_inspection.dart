/// Update inspection and debug rendering APIs.
library;

import '../doc/doc.dart';
import '../metadata/id_set.dart';
import '../structs/abstract_struct.dart';
import '../structs/id.dart';
import 'apply_update.dart';
import 'state_update.dart';

/// Immutable summary of a decoded update.
final class DecodedUpdate {
  /// Creates a decoded update summary.
  DecodedUpdate({
    required this.version,
    required Iterable<DecodedStruct> structs,
    required this.deleteSet,
    required this.hasPendingStructs,
  }) : structs = List<DecodedStruct>.unmodifiable(structs);

  /// Update format version.
  final int version;

  /// Structs visible after decoding and applying causally ready content.
  final List<DecodedStruct> structs;

  /// Delete set represented by the update.
  final IdSet deleteSet;

  /// Whether the update contained unresolved struct ranges.
  final bool hasPendingStructs;

  /// Returns a stable multi-line debug representation.
  String toDebugString() {
    final buffer = StringBuffer('update-v$version');
    if (structs.isEmpty) {
      buffer.write('\nstructs: empty');
    } else {
      for (final struct in structs) {
        buffer.write('\nstruct: ${struct.toDebugString()}');
      }
    }
    buffer
      ..write('\ndeleteSet: ')
      ..write(deleteSet.isEmpty ? 'empty' : deleteSet.toString())
      ..write('\npendingStructs: ')
      ..write(hasPendingStructs);
    return buffer.toString();
  }
}

/// Immutable summary of one decoded struct range.
final class DecodedStruct {
  /// Creates a decoded struct summary.
  const DecodedStruct({
    required this.id,
    required this.length,
    required this.ref,
    required this.kind,
    required this.deleted,
  });

  /// First id covered by the struct.
  final Id id;

  /// Number of clocks covered by the struct.
  final int length;

  /// Binary struct or content reference number.
  final int ref;

  /// Human-readable struct kind.
  final String kind;

  /// Whether this range is deleted.
  final bool deleted;

  /// Returns one stable debug line.
  String toDebugString() {
    return '${id.client.value}:${id.clock.value}+$length '
        'ref=$ref kind=$kind deleted=$deleted';
  }
}

/// Decodes a V1 [update] into an immutable summary.
DecodedUpdate decodeUpdate(List<int> update) {
  return _decode(update, version: 1);
}

/// Decodes a V2 [update] into an immutable summary.
DecodedUpdate decodeUpdateV2(List<int> update) {
  return _decode(update, version: 2);
}

/// Returns deterministic debug text for a V1 [update].
String logUpdate(List<int> update) => decodeUpdate(update).toDebugString();

/// Returns deterministic debug text for a V2 [update].
String logUpdateV2(List<int> update) => decodeUpdateV2(update).toDebugString();

DecodedUpdate _decode(List<int> update, {required int version}) {
  final doc = Doc();
  if (version == 1) {
    applyUpdate(doc, update);
  } else {
    applyUpdateV2(doc, update);
  }
  final pending = doc.store.pendingStructs;
  return DecodedUpdate(
    version: version,
    structs: [
      for (final client in doc.store.clients)
        for (final struct in doc.store.structsFor(client))
          _decodedStruct(struct),
      for (final client in pending.clients)
        for (final range in pending.rangesFor(client))
          DecodedStruct(
            id: Id(client: client, clock: range.start),
            length: range.length,
            ref: structSkipRefNumber,
            kind: 'Pending',
            deleted: false,
          ),
    ],
    deleteSet: createDeleteSetFromStore(doc.store).merged(
      doc.store.pendingDeleteSet,
    ),
    hasPendingStructs: pending.isNotEmpty,
  );
}

DecodedStruct _decodedStruct(AbstractStruct struct) {
  final kind = switch (struct) {
    GC() => 'GC',
    Skip() => 'Skip',
    Item(:final content) => 'Item:${content.runtimeType}',
    _ => struct.runtimeType.toString(),
  };
  return DecodedStruct(
    id: struct.id,
    length: struct.length,
    ref: struct.ref,
    kind: kind,
    deleted: struct.deleted,
  );
}
