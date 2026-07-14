part of 'random_convergence_harness.dart';

/// Creates a replica for a random convergence run.
typedef RandomReplicaFactory<T extends Object> = T Function(int index);

/// Captures comparable visible state for a replica.
typedef RandomSnapshot<T extends Object> = Object? Function(T replica);

/// Creates one operation for a random convergence run.
typedef RandomOperationFactory<T extends Object> = RandomConvergenceOperation<T>
    Function(
  RandomConvergenceContext<T> context,
);

/// Operation applied locally and then delivered to remote replicas.
final class RandomConvergenceOperation<T extends Object> {
  /// Creates an operation with a diagnostic [label].
  const RandomConvergenceOperation({
    required this.label,
    required this.apply,
  });

  /// Human-readable operation label included in failure traces.
  final String label;

  /// Applies this operation to one replica.
  final void Function(T replica) apply;
}

/// Context passed to random operation factories.
final class RandomConvergenceContext<T extends Object> {
  RandomConvergenceContext._({
    required this.harness,
    required this.random,
    required this.operationIndex,
    required this.originIndex,
  });

  /// Harness that owns this run.
  final RandomConvergenceHarness<T> harness;

  /// Deterministic pseudo-random generator for this run.
  final Random random;

  /// Zero-based operation index.
  final int operationIndex;

  /// Replica index where the operation originated.
  final int originIndex;

  /// Replica where the operation originated.
  T get origin => harness.replicaAt(originIndex);
}

/// Error thrown when a randomized run does not converge.
final class RandomConvergenceException implements Exception {
  /// Creates a convergence failure with reproduction details.
  const RandomConvergenceException({
    required this.seed,
    required this.command,
    required this.snapshots,
    required this.trace,
  });

  /// Failing deterministic seed.
  final int seed;

  /// Command that reruns the failing seed.
  final String command;

  /// Replica snapshots captured at failure time.
  final List<Object?> snapshots;

  /// Operation and delivery trace captured at failure time.
  final List<String> trace;

  @override
  String toString() {
    return 'Random convergence failed for seed=$seed.\n'
        'Reproduce: $command\n'
        'Snapshots: $snapshots\n'
        'Trace:\n${trace.join('\n')}';
  }
}

final class _PendingUpdate<T extends Object> {
  const _PendingUpdate({
    required this.id,
    required this.originIndex,
    required this.operation,
    this.targetIndex = -1,
  });

  final int id;
  final int originIndex;
  final int targetIndex;
  final RandomConvergenceOperation<T> operation;

  _PendingUpdate<T> forTarget(int targetIndex) {
    return _PendingUpdate<T>(
      id: id,
      originIndex: originIndex,
      targetIndex: targetIndex,
      operation: operation,
    );
  }
}
