import 'package:dart_crdt/dart_crdt.dart';
import 'package:test/test.dart';

import '../../helpers/binary_sync_harness.dart';

/// M3: root maps must now sync over the binary wire path. Before M3 a map
/// attribute encoded to an empty update and arrived missing. Conflicts resolve
/// structurally (by item-id order), not by the in-memory `clock:`.
void main() {
  // Order-independent, value-comparable snapshot for the harness check.
  String snap(Doc doc) {
    final map = doc.getMap('m');
    final keys = map.attrKeys.toList()..sort();
    return keys.map((k) => '$k=${map.getAttr(k)}').join('|');
  }

  Map<String, Object?> attrs(Doc doc) => doc.getMap('m').getAttrs();

  group('root map binary sync', () {
    test('set attributes propagate to every replica', () {
      final harness = BinarySyncHarness(replicaCount: 3, snapshot: snap);

      harness.mutate(0, (doc) {
        doc.getMap('m')
          ..setAttr('title', 'Draft')
          ..setAttr('count', 1)
          ..setAttr('nullable', null);
      });
      harness.flush();

      harness.assertConverged();
      expect(attrs(harness.replicaAt(1)), {
        'title': 'Draft',
        'count': 1,
        'nullable': null,
      });
      expect(harness.replicaAt(2).getMap('m').hasAttr('nullable'), isTrue);
    });

    test('deletes propagate over the wire', () {
      final harness = BinarySyncHarness(replicaCount: 2, snapshot: snap);

      harness.mutate(0, (doc) {
        doc.getMap('m')
          ..setAttr('a', 1)
          ..setAttr('b', 2);
      });
      harness.flush();
      expect(attrs(harness.replicaAt(1)), {'a': 1, 'b': 2});

      harness.mutate(0, (doc) => doc.getMap('m').deleteAttr('a'));
      harness.flush();

      harness.assertConverged();
      expect(harness.replicaAt(1).getMap('m').hasAttr('a'), isFalse);
      expect(attrs(harness.replicaAt(1)), {'b': 2});
    });

    test('concurrent writes to the same key converge to one winner', () {
      final harness =
          BinarySyncHarness(replicaCount: 2, snapshot: snap, seed: 3);

      // Both replicas write the same key while partitioned.
      harness.disconnect(0, 1);
      harness.mutate(0, (doc) => doc.getMap('m').setAttr('k', 'from-zero'));
      harness.mutate(1, (doc) => doc.getMap('m').setAttr('k', 'from-one'));
      harness.flush(duplicateDeliveries: 1);

      harness.reconnectAll();
      harness.flush(duplicateDeliveries: 1);
      harness.reconcileAll();

      harness.assertConverged();
      // A single deterministic winner survives on every replica.
      final winner = harness.replicaAt(0).getMap('m').getAttr('k');
      expect(winner, anyOf('from-zero', 'from-one'));
      expect(harness.replicaAt(1).getMap('m').getAttr('k'), winner);
    });

    test('a replica that missed all traffic catches up via reconcile', () {
      final harness =
          BinarySyncHarness(replicaCount: 3, snapshot: snap, seed: 11);

      harness.disconnect(2, 0);
      harness.disconnect(2, 1);
      harness.mutate(0, (doc) => doc.getMap('m').setAttr('x', 10));
      harness.mutate(1, (doc) => doc.getMap('m').setAttr('y', 20));
      harness.flush();
      expect(attrs(harness.replicaAt(2)), isEmpty);

      harness.reconnectAll();
      harness.reconcileAll();

      harness.assertConverged();
      expect(attrs(harness.replicaAt(2)), {'x': 10, 'y': 20});
    });

    test('converges over the V2 wire format too', () {
      final harness = BinarySyncHarness(
        replicaCount: 2,
        snapshot: snap,
        seed: 19,
        useV2: true,
      );

      harness.mutate(0, (doc) => doc.getMap('m').setAttr('p', 'one'));
      harness.mutate(1, (doc) => doc.getMap('m').setAttr('q', 'two'));
      harness.flush(duplicateDeliveries: 2);
      harness.reconcileAll();

      harness.assertConverged();
      expect(attrs(harness.replicaAt(0)), {'p': 'one', 'q': 'two'});
    });
  });
}
