import 'dart:math';

import 'package:dart_crdt/dart_crdt.dart';
import 'package:test/test.dart';

import '../helpers/binary_sync_harness.dart';

void main() {
  group('random shared map convergence', () {
    test('converges random key sets/deletes across a churning network', () {
      String snap(Doc doc) {
        final map = doc.getMap('attrs');
        final keys = map.attrKeys.toList()..sort();
        return keys.map((k) => '$k=${map.getAttr(k)}').join('|');
      }

      const replicaCount = 4;
      final seed = int.tryParse(
            const String.fromEnvironment('DART_CRDT_RANDOM_SEED'),
          ) ??
          202;
      final random = Random(seed);
      final harness = BinarySyncHarness(
        replicaCount: replicaCount,
        snapshot: snap,
        seed: seed,
      );

      var sawDelete = false;
      for (var op = 0; op < 80; op += 1) {
        // Network churn: toggle a random link.
        if (op % 3 == 0) {
          final a = random.nextInt(replicaCount);
          var b = random.nextInt(replicaCount);
          if (a == b) b = (b + 1) % replicaCount;
          if (harness.areConnected(a, b)) {
            harness.disconnect(a, b);
          } else {
            harness.reconnect(a, b);
          }
        }

        final origin = random.nextInt(replicaCount);
        final key = 'k${random.nextInt(5)}';
        if (op % 4 == 3) {
          sawDelete = true;
          harness.mutate(origin, (doc) => doc.getMap('attrs').deleteAttr(key));
        } else {
          harness.mutate(
            origin,
            (doc) => doc.getMap('attrs').setAttr(key, 'v$op-$origin'),
          );
        }
        harness.flush(duplicateDeliveries: 1);
      }

      // Heal the network and let anti-entropy bring everyone to a fixpoint.
      harness.reconnectAll();
      harness.flush(duplicateDeliveries: 1);
      harness.reconcileAll();

      harness.assertConverged();
      expect(sawDelete, isTrue);
      // All replicas agree on the full attribute set.
      final reference = snap(harness.replicaAt(0));
      for (var i = 1; i < replicaCount; i += 1) {
        expect(snap(harness.replicaAt(i)), reference);
      }
    });
  });
}
