import 'package:dart_crdt/src/doc/doc.dart';
import 'package:test/test.dart';

import '../helpers/random_convergence_harness.dart';
import '../helpers/random_shared_type_operations.dart';

void main() {
  group('random shared array convergence', () {
    test('converges with conflicts, late sync, nested values, and deletes', () {
      final harness = RandomConvergenceHarness<Doc>(
        seed: randomConvergenceSeed(fallback: 101),
        replicaCount: 4,
        createReplica: (_) => Doc(),
        snapshot: sequenceConvergenceSnapshot,
        testFile: 'test/integration/random_sequence_convergence_test.dart',
        plainName: 'converges with conflicts, late sync',
      );

      harness
        ..disconnect(0, 1)
        ..publish(
          originIndex: 0,
          operation: sequenceInsertOperation(id: 'late', nested: true),
        )
        ..flushPending(duplicateDeliveries: 1);

      expect(harness.pendingUpdateCount, greaterThan(0));

      harness.run(
        operationCount: 36,
        nextOperation: randomSequenceOperations(),
        networkChurnEvery: 2,
        duplicateDeliveries: 2,
      );

      final snapshots = harness.replicas.map(sequenceConvergenceSnapshot);
      final uniqueSnapshots = snapshots.toSet();
      expect(uniqueSnapshots, hasLength(1));
      expect(uniqueSnapshots.single, contains('nested:late'));
      expect(_traceContains(harness, 'array insert nested'), isTrue);
      expect(_traceContains(harness, 'array delete'), isTrue);
      expect(_traceContains(harness, 'duplicate'), isTrue);
      expect(_traceContains(harness, 'disconnect'), isTrue);
      expect(_traceContains(harness, 'reconnect'), isTrue);
    });
  });
}

bool _traceContains(RandomConvergenceHarness<Doc> harness, String text) {
  return harness.trace.any((entry) => entry.contains(text));
}
