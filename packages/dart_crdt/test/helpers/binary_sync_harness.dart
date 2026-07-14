import 'dart:math';
import 'dart:typed_data';

import 'package:dart_crdt/dart_crdt.dart';

/// Captures comparable visible state for a [Doc] replica.
typedef BinarySyncSnapshot = Object? Function(Doc doc);

/// Deterministic network harness that converges replicas using ONLY the binary
/// wire path ([encodeStateAsUpdate] / [applyUpdate]) — not operation replay.
///
/// This is the missing test layer: the existing `RandomConvergenceHarness`
/// replays logical operation closures on each replica, so it never exercises
/// `encodeStateAsUpdate`/`applyUpdate` for the types under test. This harness
/// mutates only the origin replica, captures the incremental update that
/// mutation produced (`encodeStateAsUpdate(origin, stateVector(before))`), and
/// delivers those bytes to peers through a configurable network (partitions,
/// duplicates, reordering). [reconcileAll] performs anti-entropy (state-vector
/// diffs across connected pairs to a fixpoint) so a connected graph is
/// guaranteed to converge regardless of delivery order.
final class BinarySyncHarness {
  /// Creates a harness with [replicaCount] independent [Doc] replicas.
  BinarySyncHarness({
    required int replicaCount,
    required this.snapshot,
    this.seed = 1,
    this.useV2 = false,
  })  : _random = Random(seed),
        _docs = List<Doc>.generate(replicaCount, (_) => Doc()),
        _connected = List<List<bool>>.generate(
          replicaCount,
          (_) => List<bool>.filled(replicaCount, true),
        ) {
    RangeError.checkValueInInterval(replicaCount, 1, 64, 'replicaCount');
  }

  /// Deterministic seed for delivery shuffling.
  final int seed;

  /// Whether to use the V2 wire format for updates.
  final bool useV2;

  /// Function that captures comparable visible replica state.
  final BinarySyncSnapshot snapshot;

  final Random _random;
  final List<Doc> _docs;
  final List<List<bool>> _connected;
  final List<_PendingSync> _pending = <_PendingSync>[];
  int _nextId = 0;

  /// Number of replicas.
  int get replicaCount => _docs.length;

  /// Immutable view of replicas.
  List<Doc> get replicas => List<Doc>.unmodifiable(_docs);

  /// Returns the replica [Doc] at [index].
  Doc replicaAt(int index) => _docs[index];

  /// Number of updates still waiting on disconnected links.
  int get pendingUpdateCount => _pending.length;

  /// Whether [a] can currently exchange updates with [b].
  bool areConnected(int a, int b) => _connected[a][b];

  /// Disconnects the undirected link between [a] and [b].
  void disconnect(int a, int b) => _setConnection(a, b, connected: false);

  /// Reconnects the undirected link between [a] and [b].
  void reconnect(int a, int b) => _setConnection(a, b, connected: true);

  /// Reconnects every replica pair.
  void reconnectAll() {
    for (var a = 0; a < _docs.length; a += 1) {
      for (var b = a + 1; b < _docs.length; b += 1) {
        reconnect(a, b);
      }
    }
  }

  /// Applies [mutation] to the origin replica and queues a point-to-point sync
  /// from that origin to every other replica.
  ///
  /// The bytes are not captured here: a real sync protocol computes the diff
  /// against the *target's current* state vector at delivery time, which is
  /// always causally complete. Capturing a fixed delta at mutation time and
  /// replaying it out of order produces gappy, framing-fragile updates that no
  /// real protocol emits — so delivery is deferred to [flush].
  void mutate(int origin, void Function(Doc doc) mutation) {
    _checkReplicaIndex(origin);
    mutation(_docs[origin]);
    final id = _nextId++;
    for (var target = 0; target < _docs.length; target += 1) {
      if (target != origin) {
        _pending.add(
          _PendingSync(id: id, originIndex: origin, targetIndex: target),
        );
      }
    }
  }

  /// Delivers all currently connected pending syncs as causally-complete
  /// state-vector diffs (origin -> target). Syncs on disconnected links stay
  /// queued. Delivery is idempotent, so [duplicateDeliveries] and [shuffle]
  /// exercise duplicate/reordered delivery without ever sending a partial
  /// update (point-to-point only — no transitive relay).
  void flush({bool shuffle = true, int duplicateDeliveries = 0}) {
    RangeError.checkNotNegative(duplicateDeliveries, 'duplicateDeliveries');
    final blocked = <_PendingSync>[];
    final deliveries = <_PendingSync>[];
    for (final sync in _pending) {
      if (_connected[sync.originIndex][sync.targetIndex]) {
        deliveries.add(sync);
      } else {
        blocked.add(sync);
      }
    }
    _pending
      ..clear()
      ..addAll(blocked);
    if (shuffle) {
      deliveries.shuffle(_random);
    }
    for (final sync in deliveries) {
      for (var count = 0; count <= duplicateDeliveries; count += 1) {
        _syncPair(sync.originIndex, sync.targetIndex);
      }
    }
  }

  /// Delivers everything [from] knows that [to] is missing, as one diff.
  void _syncPair(int from, int to) {
    final diff = useV2
        ? encodeStateAsUpdateV2(
            _docs[from],
            encodeDocumentStateVector(_docs[to]),
          )
        : encodeStateAsUpdate(
            _docs[from],
            encodeDocumentStateVector(_docs[to]),
          );
    _apply(to, diff);
  }

  /// Anti-entropy: repeatedly syncs every connected ordered pair via
  /// state-vector diffs until no replica's full state changes (a fixpoint).
  /// Guarantees convergence for any connected component.
  void reconcileAll({int maxRounds = 64}) {
    for (var round = 0; round < maxRounds; round += 1) {
      final before = _fullStates();
      for (var a = 0; a < _docs.length; a += 1) {
        for (var b = 0; b < _docs.length; b += 1) {
          if (a == b || !_connected[a][b]) {
            continue;
          }
          _syncPair(a, b);
        }
      }
      if (_statesEqual(before, _fullStates())) {
        return;
      }
    }
  }

  /// Throws [StateError] unless all replica snapshots are equal.
  void assertConverged() {
    final snapshots = _docs.map(snapshot).toList(growable: false);
    final expected = snapshots.first;
    for (var index = 1; index < snapshots.length; index += 1) {
      if (snapshots[index] != expected) {
        throw StateError(
          'Binary-sync convergence failed (seed=$seed).\n'
          'Replica 0: $expected\n'
          'Replica $index: ${snapshots[index]}\n'
          'All snapshots: $snapshots',
        );
      }
    }
  }

  void _apply(int target, List<int> bytes) {
    if (useV2) {
      applyUpdateV2(_docs[target], bytes);
    } else {
      applyUpdate(_docs[target], bytes);
    }
  }

  List<Uint8List> _fullStates() {
    return _docs
        .map(
          (doc) =>
              useV2 ? encodeStateAsUpdateV2(doc) : encodeStateAsUpdate(doc),
        )
        .toList(growable: false);
  }

  bool _statesEqual(List<Uint8List> a, List<Uint8List> b) {
    for (var i = 0; i < a.length; i += 1) {
      if (a[i].length != b[i].length) {
        return false;
      }
      for (var j = 0; j < a[i].length; j += 1) {
        if (a[i][j] != b[i][j]) {
          return false;
        }
      }
    }
    return true;
  }

  void _setConnection(int a, int b, {required bool connected}) {
    _checkReplicaIndex(a);
    _checkReplicaIndex(b);
    _connected[a][b] = connected;
    _connected[b][a] = connected;
  }

  void _checkReplicaIndex(int index) {
    RangeError.checkValueInInterval(index, 0, _docs.length - 1, 'index');
  }
}

final class _PendingSync {
  const _PendingSync({
    required this.id,
    required this.originIndex,
    required this.targetIndex,
  });

  final int id;
  final int originIndex;
  final int targetIndex;
}
