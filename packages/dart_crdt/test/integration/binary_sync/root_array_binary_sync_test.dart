import 'package:dart_crdt/dart_crdt.dart';
import 'package:test/test.dart';

import '../../helpers/binary_sync_harness.dart';

/// M2: root arrays must now sync over the binary wire path. Before M2 a 3-element
/// array encoded to an empty 2-byte update and arrived as `[]`; these tests
/// exercise real `encodeStateAsUpdate`/`applyUpdate` round-trips.
void main() {
  // Stable, value-comparable snapshot for the harness convergence check.
  String snap(Doc doc) => doc.getArray('a').toArray().toString();
  List<Object?> array(Doc doc) => doc.getArray('a').toArray();

  group('root array binary sync', () {
    test('inserted scalars propagate to every replica', () {
      final harness = BinarySyncHarness(replicaCount: 3, snapshot: snap);

      harness.mutate(0, (doc) => doc.getArray('a').insertAll(0, [1, 'two', 3]));
      harness.flush();

      harness.assertConverged();
      expect(array(harness.replicaAt(1)), [1, 'two', 3]);
      expect(array(harness.replicaAt(2)), [1, 'two', 3]);
    });

    test('deletes propagate over the wire', () {
      final harness = BinarySyncHarness(replicaCount: 2, snapshot: snap);

      harness.mutate(
        0,
        (doc) => doc.getArray('a').insertAll(0, ['a', 'b', 'c', 'd']),
      );
      harness.flush();
      expect(array(harness.replicaAt(1)), ['a', 'b', 'c', 'd']);

      harness.mutate(0, (doc) => doc.getArray('a').delete(1, 2));
      harness.flush();

      harness.assertConverged();
      expect(array(harness.replicaAt(1)), ['a', 'd']);
    });

    test('concurrent inserts across a partition converge after reconcile', () {
      final harness =
          BinarySyncHarness(replicaCount: 3, snapshot: snap, seed: 5);

      harness.mutate(0, (doc) => doc.getArray('a').insertAll(0, ['base']));
      harness.flush();

      harness.disconnect(0, 1);
      harness.mutate(0, (doc) => doc.getArray('a').push('from-zero'));
      harness.mutate(1, (doc) => doc.getArray('a').unshift('from-one'));
      harness.flush(duplicateDeliveries: 1);

      harness.reconnectAll();
      harness.flush(duplicateDeliveries: 1);
      harness.reconcileAll();

      harness.assertConverged();
      final merged = array(harness.replicaAt(0));
      expect(merged, containsAll(<Object?>['base', 'from-zero', 'from-one']));
      expect(merged.length, 3);
    });

    test('a replica that missed all traffic catches up via reconcile', () {
      final harness =
          BinarySyncHarness(replicaCount: 3, snapshot: snap, seed: 9);

      harness.disconnect(2, 0);
      harness.disconnect(2, 1);
      harness.mutate(0, (doc) => doc.getArray('a').insertAll(0, [10, 20]));
      harness.mutate(1, (doc) => doc.getArray('a').insertAll(0, [30]));
      harness.flush();
      expect(array(harness.replicaAt(2)), isEmpty);

      harness.reconnectAll();
      harness.reconcileAll();

      harness.assertConverged();
      expect(array(harness.replicaAt(2)).length, 3);
    });

    test('converges over the V2 wire format too', () {
      final harness = BinarySyncHarness(
        replicaCount: 2,
        snapshot: snap,
        seed: 17,
        useV2: true,
      );

      harness.mutate(0, (doc) => doc.getArray('a').insertAll(0, ['x', 'y']));
      harness.mutate(1, (doc) => doc.getArray('a').unshift('z'));
      harness.flush(duplicateDeliveries: 2);
      harness.reconcileAll();

      harness.assertConverged();
      expect(array(harness.replicaAt(0)).length, 3);
    });
  });
}
