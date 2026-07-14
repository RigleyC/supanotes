import 'package:dart_crdt/src/doc/doc.dart';
import 'package:test/test.dart';

import '../helpers/random_convergence_harness.dart';

void main() {
  group('RandomConvergenceHarness', () {
    test('converges with deterministic shuffled duplicate delivery', () {
      final seed = randomConvergenceSeed(fallback: 37);
      final harness = RandomConvergenceHarness<Doc>(
        seed: seed,
        replicaCount: 4,
        createReplica: (_) => Doc(),
        snapshot: _sharedMapSnapshot,
        plainName: 'converges with deterministic shuffled duplicate delivery',
      );

      harness.run(
        operationCount: 24,
        nextOperation: (context) {
          final key = 'k${context.operationIndex}';
          final value = 'r${context.originIndex}:${context.random.nextInt(99)}';
          return RandomConvergenceOperation<Doc>(
            label: 'set $key',
            apply: (doc) {
              doc.get('shared').setAttr(
                    key,
                    value,
                    clock: context.operationIndex + 1,
                  );
            },
          );
        },
      );

      expect(harness.pendingUpdateCount, 0);
      expect(harness.trace, contains(startsWith('disconnect')));
      expect(harness.trace, contains(startsWith('duplicate')));
      expect(
        harness.replicas.map(_sharedMapSnapshot).toSet(),
        hasLength(1),
      );
    });

    test('keeps disconnected updates pending until reconnect', () {
      final harness = RandomConvergenceHarness<Doc>(
        seed: 11,
        replicaCount: 2,
        createReplica: (_) => Doc(),
        snapshot: _sharedMapSnapshot,
      );

      harness.disconnect(0, 1);
      harness.publish(
        originIndex: 0,
        operation: RandomConvergenceOperation<Doc>(
          label: 'set late',
          apply: (doc) {
            doc.get('shared').setAttr('late', true);
          },
        ),
      );
      harness.flushPending();

      expect(harness.pendingUpdateCount, 1);
      expect(_sharedMapSnapshot(harness.replicaAt(0)), 'late=true');
      expect(_sharedMapSnapshot(harness.replicaAt(1)), isEmpty);

      harness.reconnect(0, 1);
      harness.flushPending(duplicateDeliveries: 2);
      harness.assertConverged();

      expect(harness.pendingUpdateCount, 0);
      expect(harness.trace, contains('duplicate #0 r1'));
    });

    test('reports seed, command, snapshots, and trace on failure', () {
      final harness = RandomConvergenceHarness<_ReplicaState>(
        seed: 5,
        replicaCount: 2,
        createReplica: _ReplicaState.new,
        snapshot: (replica) => replica.index,
        plainName: 'reports seed, command, snapshots, and trace on failure',
      );

      harness.publish(
        originIndex: 0,
        operation: RandomConvergenceOperation<_ReplicaState>(
          label: 'noop',
          apply: (_) {},
        ),
      );
      harness.flushPending();

      expect(
        harness.assertConverged,
        throwsA(
          isA<RandomConvergenceException>()
              .having((error) => error.seed, 'seed', 5)
              .having(
                (error) => error.command,
                'command',
                contains('DART_CRDT_RANDOM_SEED=5'),
              )
              .having((error) => error.snapshots, 'snapshots', [0, 1]).having(
            (error) => error.trace.join('\n'),
            'trace',
            contains('noop'),
          ),
        ),
      );
    });

    test('keeps long runs opt-in through environment gates', () {
      expect(
        shouldRunLongRandomConvergenceTests(environment: const {}),
        isFalse,
      );
      expect(
        shouldRunLongRandomConvergenceTests(
          environment: const {'DART_CRDT_LONG_RANDOM': '1'},
        ),
        isTrue,
      );
      expect(
        randomConvergenceSeed(
          fallback: 13,
          environment: const {'DART_CRDT_RANDOM_SEED': '21'},
        ),
        21,
      );
    });
  });
}

String _sharedMapSnapshot(Doc doc) {
  final attrs = doc.get('shared').getAttrs();
  final entries = attrs.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  return entries.map((entry) => '${entry.key}=${entry.value}').join('|');
}

final class _ReplicaState {
  const _ReplicaState(this.index);

  final int index;
}
