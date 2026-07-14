import 'package:dart_crdt/src/doc/doc.dart';
import 'package:test/test.dart';

import '../helpers/random_convergence_harness.dart';
import '../helpers/random_shared_type_operations.dart';

void main() {
  group('random shared text convergence', () {
    test('converges with insert/delete conflicts, late sync, and duplicates',
        () {
      final harness = RandomConvergenceHarness<Doc>(
        seed: randomConvergenceSeed(fallback: 303),
        replicaCount: 4,
        createReplica: (_) => Doc(),
        snapshot: textConvergenceSnapshot,
        testFile: 'test/integration/random_text_convergence_test.dart',
        plainName: 'converges with insert/delete conflicts, late sync',
      );

      harness
        ..disconnect(0, 1)
        ..publish(
          originIndex: 0,
          operation: textInsertOperation(token: 777, origin: 0),
        )
        ..flushPending(duplicateDeliveries: 1);

      expect(harness.pendingUpdateCount, greaterThan(0));

      harness.run(
        operationCount: 36,
        nextOperation: randomTextOperations(),
        networkChurnEvery: 2,
        duplicateDeliveries: 2,
      );

      final snapshots = harness.replicas.map(textConvergenceSnapshot);
      final uniqueSnapshots = snapshots.toSet();
      expect(uniqueSnapshots, hasLength(1));
      expect(uniqueSnapshots.single, contains('"token":777'));
      expect(_traceContains(harness, 'text insert'), isTrue);
      expect(_traceContains(harness, 'text delete'), isTrue);
      expect(_traceContains(harness, 'duplicate'), isTrue);
      expect(_traceContains(harness, 'disconnect'), isTrue);
      expect(_traceContains(harness, 'reconnect'), isTrue);
    });
  });
}

bool _traceContains(RandomConvergenceHarness<Doc> harness, String text) {
  return harness.trace.any((entry) => entry.contains(text));
}
