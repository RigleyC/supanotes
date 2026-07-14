part of 'snapshot.dart';

/// Thrown when a snapshot cannot be restored against a document.
final class SnapshotRestoreException implements Exception {
  /// Creates a restore exception with a domain-specific [reason].
  const SnapshotRestoreException(this.reason);

  /// The restore failure reason.
  final String reason;

  @override
  String toString() => 'SnapshotRestoreException: $reason';
}

/// Splits source structs at boundaries that [snapshot] may restore or delete.
///
/// Example:
/// ```dart
/// final doc = Doc(gc: false);
/// final snap = snapshot(doc);
/// splitSnapshotAffectedStructs(doc, snap);
/// ```
void splitSnapshotAffectedStructs(Doc document, Snapshot snapshot) {
  _validateSnapshotForDocument(document, snapshot);
  for (final entry in snapshot._stateVector.entries) {
    _cleanBoundary(document, entry.key, entry.value.value);
  }
  snapshot._deleteSet.forEach((client, range) {
    _cleanBoundary(document, client, range.start.value);
    _cleanBoundary(document, client, range.end);
  });
}

/// Creates a document restored to [snapshot] from [originDocument].
///
/// [originDocument] must have garbage collection disabled so deleted content
/// needed by the snapshot is still available.
///
/// Example:
/// ```dart
/// final origin = Doc(gc: false);
/// final snap = snapshot(origin);
/// final restored = createDocFromSnapshot(origin, snap);
/// ```
Doc createDocFromSnapshot(
  Doc originDocument,
  Snapshot snapshot, {
  Doc? target,
  Object? origin,
}) {
  if (originDocument.gc) {
    throw const SnapshotRestoreException(
      'Cannot restore from a document with garbage collection enabled.',
    );
  }

  final update = originDocument.transact(
    (_) {
      splitSnapshotAffectedStructs(originDocument, snapshot);
      return encodeStateAsSnapshotUpdateV2(
        originDocument,
        snapshot._stateVector,
        snapshot._deleteSet,
      );
    },
    origin: origin ?? snapshot,
  );
  final restored = target ?? Doc();
  applyUpdateV2(restored, update, origin: origin ?? snapshot);
  return restored;
}

/// Returns whether a V1 [update] is fully contained by [snapshot].
bool snapshotContainsUpdate(Snapshot snapshot, List<int> update) {
  return _snapshotContainsDecoded(snapshot, decodeUpdate(update));
}

/// Returns whether a V2 [update] is fully contained by [snapshot].
bool snapshotContainsUpdateV2(Snapshot snapshot, List<int> update) {
  return _snapshotContainsDecoded(snapshot, decodeUpdateV2(update));
}

bool _snapshotContainsDecoded(Snapshot snapshot, DecodedUpdate update) {
  for (final struct in update.structs) {
    final snapshotClock = snapshot._stateVector[struct.id.client]?.value ?? 0;
    if (snapshotClock < struct.id.clock.value + struct.length) {
      return false;
    }
  }
  if (update.deleteSet.diff(snapshot._deleteSet).isNotEmpty) {
    return false;
  }
  for (final client in update.deleteSet.clients) {
    final snapshotClock = snapshot._stateVector[client]?.value ?? 0;
    for (final range in update.deleteSet.rangesFor(client)) {
      if (snapshotClock < range.end) {
        return false;
      }
    }
  }
  return true;
}

void _validateSnapshotForDocument(Doc document, Snapshot snapshot) {
  for (final entry in snapshot._stateVector.entries) {
    final storeClock = document.store.getClock(entry.key).value;
    if (entry.value.value > storeClock) {
      throw SnapshotRestoreException(
        'Snapshot clock ${entry.value.value} exceeds stored clock '
        '$storeClock for client ${entry.key.value}.',
      );
    }
  }
  snapshot._deleteSet.forEach((client, range) {
    final snapshotClock = snapshot._stateVector[client]?.value ?? 0;
    if (range.end > snapshotClock) {
      throw SnapshotRestoreException(
        'Snapshot delete range $range exceeds state clock $snapshotClock '
        'for client ${client.value}.',
      );
    }
    final storeClock = document.store.getClock(client).value;
    if (range.end > storeClock) {
      throw SnapshotRestoreException(
        'Snapshot delete range $range exceeds stored clock $storeClock '
        'for client ${client.value}.',
      );
    }
  });
}

void _cleanBoundary(Doc document, ClientId client, int clock) {
  final storeClock = document.store.getClock(client).value;
  if (clock <= 0 || clock >= storeClock) {
    return;
  }
  final id = Id(client: client, clock: Clock(clock));
  if (document.store.structContaining(id) != null) {
    document.store.cleanStart(id);
  }
}
