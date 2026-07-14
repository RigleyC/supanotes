import 'package:dart_crdt/src/content/content.dart';
import 'package:dart_crdt/src/doc/doc.dart';
import 'package:test/test.dart';

import '../../helpers/random_convergence_harness.dart';
import '../../helpers/random_shared_type_operations.dart';
import '../../helpers/shared_regression_fixture.dart';

void main() {
  group('shared sequence regressions', () {
    test('detaches deleted children and reindexes surviving children', () {
      final doc = Doc();
      final array = doc.get('items', SharedTypeKind.array);
      final removed = SharedType(kind: SharedTypeKind.map, name: 'removed');
      final kept = SharedType(kind: SharedTypeKind.text, name: 'kept');
      final deepEvents = <String>[];

      array.observeDeep((event) {
        deepEvents.add('${event.target.name}:${event.keys.join(',')}');
      });

      array
        ..push('before')
        ..push(removed)
        ..push(kept);
      removed.setAttr('id', 'removed');
      kept.insertText(0, 'kept');

      array.delete(1);
      kept.insertText(4, '!');

      expect(array.toArray(), ['before', kept]);
      expect(removed.parent, isNull);
      expect(removed.parentKey, isNull);
      expect(kept.parent, same(array));
      expect(kept.parentKey, 1);
      expect(array.children, isNot(contains(2)));
      expect(deepEvents, contains('kept:4'));
    });

    test('covers fixture-backed late sync, disconnects, and duplicates', () {
      final scenario = sharedRegressionScenario('sequence');
      final harness = RandomConvergenceHarness<Doc>(
        seed: scenario.seed,
        replicaCount: scenario.replicaCount,
        createReplica: (_) => Doc(),
        snapshot: sequenceConvergenceSnapshot,
        testFile: 'test/integration/shared/sequence_regression_test.dart',
        plainName: 'fixture-backed late sync',
      );

      harness
        ..disconnect(0, 1)
        ..publish(
          originIndex: 0,
          operation: sequenceInsertOperation(id: 'fixture', nested: true),
        )
        ..flushPending(duplicateDeliveries: scenario.duplicateDeliveries);

      expect(harness.pendingUpdateCount, greaterThan(0));

      harness.run(
        operationCount: scenario.operationCount,
        nextOperation: randomSequenceOperations(),
        networkChurnEvery: scenario.networkChurnEvery,
        duplicateDeliveries: scenario.duplicateDeliveries,
      );

      final uniqueSnapshots =
          harness.replicas.map(sequenceConvergenceSnapshot).toSet();
      expect(uniqueSnapshots, hasLength(1));
      expect(uniqueSnapshots.single, contains('nested:fixture'));
      expect(_traceContains(harness, 'disconnect'), isTrue);
      expect(_traceContains(harness, 'duplicate'), isTrue);
    });
  });
}

bool _traceContains(RandomConvergenceHarness<Doc> harness, String text) {
  return harness.trace.any((entry) => entry.contains(text));
}
