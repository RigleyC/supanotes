import 'package:dart_crdt/dart_crdt.dart';
import 'package:test/test.dart';

import '../../helpers/advanced_regression_helpers.dart';

void main() {
  group('advanced snapshot regressions', () {
    test('rejects snapshots beyond the available document state', () {
      final origin = advancedTextDoc(1, 'abc');
      final futureClock = createSnapshot(IdSet(), {ClientId(1): Clock(4)});
      final invalidDeletes = IdSet()
        ..addRange(ClientId(1), IdRange(start: Clock(1), length: 2));
      final deletePastState = createSnapshot(
        invalidDeletes,
        {ClientId(1): Clock(2)},
      );

      expect(
        () => createDocFromSnapshot(origin, futureClock),
        throwsA(isA<SnapshotRestoreException>()),
      );
      expect(
        () => createDocFromSnapshot(origin, deletePastState),
        throwsA(isA<SnapshotRestoreException>()),
      );
    });

    test('restores into provided target and preserves update origin', () {
      final origin = advancedTextDoc(2, 'restore me');
      final snap = snapshot(origin);
      final target = Doc(gc: false);
      final marker = Object();
      final updateEvents = <DocUpdateEvent>[];
      target.updateV2.add(updateEvents.add);

      final restored = createDocFromSnapshot(
        origin,
        snap,
        target: target,
        origin: marker,
      );

      expect(identical(restored, target), isTrue);
      expect(advancedRootText(target), 'restore me');
      expect(updateEvents, hasLength(1));
      expect(updateEvents.single.origin, same(marker));
      expect(updateEvents.single.local, isFalse);
      expect(updateEvents.single.version, 2);
    });
  });
}
