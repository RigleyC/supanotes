import 'dart:io';
import 'dart:math';

part 'random_convergence_harness_state.dart';

/// Reads the deterministic random seed from the test environment.
int randomConvergenceSeed({
  int fallback = 1,
  Map<String, String>? environment,
}) {
  final value = (environment ?? Platform.environment)['DART_CRDT_RANDOM_SEED'];
  return int.tryParse(value ?? '') ?? fallback;
}

/// Returns whether scheduled long random scenarios should run.
bool shouldRunLongRandomConvergenceTests({
  Map<String, String>? environment,
}) {
  return (environment ?? Platform.environment)['DART_CRDT_LONG_RANDOM'] == '1';
}

/// Deterministic network and delivery harness for convergence tests.
final class RandomConvergenceHarness<T extends Object> {
  /// Creates a harness with [replicaCount] independent replicas.
  RandomConvergenceHarness({
    required this.seed,
    required int replicaCount,
    required RandomReplicaFactory<T> createReplica,
    required this.snapshot,
    this.testFile = 'test/integration/random_convergence_harness_test.dart',
    this.plainName = 'random convergence',
  })  : _random = Random(seed),
        _replicas = List<T>.generate(replicaCount, createReplica),
        _connected = List<List<bool>>.generate(
          replicaCount,
          (_) => List<bool>.filled(replicaCount, true),
        ),
        _seenUpdateIds = List<Set<int>>.generate(replicaCount, (_) => <int>{}) {
    RangeError.checkValueInInterval(replicaCount, 1, 64, 'replicaCount');
  }

  /// Seed used by the deterministic pseudo-random generator.
  final int seed;

  /// Function that captures comparable visible replica state.
  final RandomSnapshot<T> snapshot;

  /// Test file included in reproduction commands.
  final String testFile;

  /// Plain-name filter included in reproduction commands.
  final String plainName;

  final Random _random;
  final List<T> _replicas;
  final List<List<bool>> _connected;
  final List<Set<int>> _seenUpdateIds;
  final List<_PendingUpdate<T>> _pending = <_PendingUpdate<T>>[];
  final List<String> _trace = <String>[];
  int _nextUpdateId = 0;

  /// Immutable snapshot of replicas.
  List<T> get replicas => List<T>.unmodifiable(_replicas);

  /// Immutable diagnostic trace for reproducing failures.
  List<String> get trace => List<String>.unmodifiable(_trace);

  /// Number of updates still waiting on disconnected links.
  int get pendingUpdateCount => _pending.length;

  /// Returns the replica at [index].
  T replicaAt(int index) {
    _checkReplicaIndex(index);
    return _replicas[index];
  }

  /// Returns whether [a] can currently exchange updates with [b].
  bool areConnected(int a, int b) {
    _checkReplicaIndex(a);
    _checkReplicaIndex(b);
    return _connected[a][b];
  }

  /// Disconnects the undirected link between [a] and [b].
  void disconnect(int a, int b) {
    _setConnection(a, b, connected: false);
  }

  /// Reconnects the undirected link between [a] and [b].
  void reconnect(int a, int b) {
    _setConnection(a, b, connected: true);
  }

  /// Reconnects every replica pair.
  void reconnectAll() {
    for (var a = 0; a < _replicas.length; a += 1) {
      for (var b = a + 1; b < _replicas.length; b += 1) {
        reconnect(a, b);
      }
    }
  }

  /// Applies [operation] locally and queues it for all remote replicas.
  void publish({
    required int originIndex,
    required RandomConvergenceOperation<T> operation,
  }) {
    _checkReplicaIndex(originIndex);
    final update = _PendingUpdate<T>(
      id: _nextUpdateId,
      originIndex: originIndex,
      operation: operation,
    );
    _nextUpdateId += 1;
    _trace.add('publish #${update.id} r$originIndex ${operation.label}');
    _applyUpdate(update, originIndex);
    for (var target = 0; target < _replicas.length; target += 1) {
      if (target != originIndex) {
        _pending.add(update.forTarget(target));
      }
    }
  }

  /// Delivers all currently connected pending updates.
  void flushPending({
    bool shuffle = true,
    int duplicateDeliveries = 0,
  }) {
    RangeError.checkNotNegative(duplicateDeliveries, 'duplicateDeliveries');
    final blocked = <_PendingUpdate<T>>[];
    final deliveries = <_PendingUpdate<T>>[];
    for (final update in _pending) {
      if (areConnected(update.originIndex, update.targetIndex)) {
        for (var count = 0; count <= duplicateDeliveries; count += 1) {
          deliveries.add(update);
        }
      } else {
        blocked.add(update);
      }
    }
    _pending
      ..clear()
      ..addAll(blocked);
    if (shuffle) {
      deliveries.shuffle(_random);
    }
    for (final update in deliveries) {
      _applyUpdate(update, update.targetIndex);
    }
  }

  /// Runs [operationCount] random operations and asserts final convergence.
  void run({
    required int operationCount,
    required RandomOperationFactory<T> nextOperation,
    int networkChurnEvery = 3,
    int duplicateDeliveries = 1,
  }) {
    RangeError.checkNotNegative(operationCount, 'operationCount');
    for (var index = 0; index < operationCount; index += 1) {
      if (networkChurnEvery > 0 && index % networkChurnEvery == 0) {
        _toggleRandomConnection();
      }
      final originIndex = _random.nextInt(_replicas.length);
      final operation = nextOperation(
        RandomConvergenceContext<T>._(
          harness: this,
          random: _random,
          operationIndex: index,
          originIndex: originIndex,
        ),
      );
      publish(originIndex: originIndex, operation: operation);
      flushPending(duplicateDeliveries: duplicateDeliveries);
    }
    reconnectAll();
    flushPending(duplicateDeliveries: duplicateDeliveries);
    assertConverged();
  }

  /// Throws [RandomConvergenceException] unless all snapshots match.
  void assertConverged() {
    final snapshots = _replicas.map(snapshot).toList(growable: false);
    final expected = snapshots.first;
    for (var index = 1; index < snapshots.length; index += 1) {
      if (snapshots[index] != expected) {
        throw RandomConvergenceException(
          seed: seed,
          command: reproductionCommand(),
          snapshots: snapshots,
          trace: trace,
        );
      }
    }
  }

  /// Reproduction command for a failing seed.
  String reproductionCommand() {
    return 'DART_CRDT_RANDOM_SEED=$seed dart test $testFile '
        '--plain-name "$plainName"';
  }

  void _applyUpdate(_PendingUpdate<T> update, int targetIndex) {
    if (!_seenUpdateIds[targetIndex].add(update.id)) {
      _trace.add('duplicate #${update.id} r$targetIndex');
      return;
    }
    update.operation.apply(_replicas[targetIndex]);
    _trace.add('apply #${update.id} r$targetIndex');
  }

  void _setConnection(int a, int b, {required bool connected}) {
    _checkReplicaIndex(a);
    _checkReplicaIndex(b);
    if (a == b) {
      return;
    }
    _connected[a][b] = connected;
    _connected[b][a] = connected;
    _trace.add(connected ? 'reconnect r$a r$b' : 'disconnect r$a r$b');
  }

  void _toggleRandomConnection() {
    if (_replicas.length < 2) {
      return;
    }
    final a = _random.nextInt(_replicas.length);
    var b = _random.nextInt(_replicas.length - 1);
    if (b >= a) {
      b += 1;
    }
    _setConnection(a, b, connected: !areConnected(a, b));
  }

  void _checkReplicaIndex(int index) {
    RangeError.checkValueInInterval(index, 0, _replicas.length - 1, 'index');
  }
}
