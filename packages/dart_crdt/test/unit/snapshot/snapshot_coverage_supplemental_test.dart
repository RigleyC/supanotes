import 'package:dart_crdt/src/doc/doc.dart';
import 'package:dart_crdt/src/metadata/id_range.dart';
import 'package:dart_crdt/src/metadata/id_set.dart';
import 'package:dart_crdt/src/snapshot/snapshot.dart';
import 'package:dart_crdt/src/structs/id.dart';
import 'package:test/test.dart';

void main() {
  group('snapshot supplemental coverage', () {
    test(
        'covers diagnostics, inequality, string rendering, and validation errors',
        () {
      final deleteSet = IdSet()..add(_id(1, 0));
      final snap =
          Snapshot(deleteSet: deleteSet, stateVector: {ClientId(1): Clock(1)});
      const malformed = MalformedSnapshotException(
        offset: 1,
        reason: 'bad',
        source: 'bytes',
      );

      expect(malformed.source, 'bytes');
      expect(malformed.toString(), contains(malformed.message));
      expect(snap.toString(), contains('Snapshot'));
      expect(snap == Snapshot(stateVector: {ClientId(1): Clock(1)}), isFalse);
      expect(
        Snapshot(stateVector: {ClientId(1): Clock(1)}) ==
            Snapshot(stateVector: {ClientId(2): Clock(1)}),
        isFalse,
      );
      expect(
        const SnapshotRestoreException('bad').toString(),
        'SnapshotRestoreException: bad',
      );
      expect(
        () => splitSnapshotAffectedStructs(
          Doc(gc: false),
          Snapshot(stateVector: {ClientId(1): Clock(1)}),
        ),
        throwsA(isA<SnapshotRestoreException>()),
      );
      expect(
        () => splitSnapshotAffectedStructs(
          Doc(gc: false),
          Snapshot(
            deleteSet: IdSet()..addRange(ClientId(1), _range(0, 1)),
            stateVector: {ClientId(1): Clock(0)},
          ),
        ),
        throwsA(isA<SnapshotRestoreException>()),
      );
      expect(
        () => splitSnapshotAffectedStructs(
          Doc(gc: false),
          Snapshot(
            deleteSet: IdSet()..addRange(ClientId(1), _range(0, 1)),
            stateVector: {ClientId(1): Clock(1)},
          ),
        ),
        throwsA(isA<SnapshotRestoreException>()),
      );
    });
  });
}

Id _id(int client, int clock) {
  return Id(client: ClientId(client), clock: Clock(clock));
}

IdRange _range(int start, int length) {
  return IdRange(start: Clock(start), length: length);
}
