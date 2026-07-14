part of '../js_smoke.dart';

Map<String, Object?> _randomConvergenceSmoke({required int version}) {
  final random = Random(8601 + version);
  final network = _UpdateNetwork(
    version: version,
    random: random,
    replicaCount: 4,
  );
  final insertedClients = <int>[];

  for (var index = 0; index < 36; index += 1) {
    if (index % 4 == 0) {
      network.toggleRandomLink();
    }
    final origin = random.nextInt(network.replicaCount);
    if (index % 5 == 4 && insertedClients.isNotEmpty) {
      final targetClient =
          insertedClients[random.nextInt(insertedClients.length)];
      network.publish(
        origin: origin,
        update: _deleteUpdate(client: targetClient, version: version),
      );
    } else {
      final client = 1000 + index;
      insertedClients.add(client);
      network.publish(
        origin: origin,
        update: _insertUpdate(
          client: client,
          text: String.fromCharCode('a'.codeUnitAt(0) + (index % 26)),
          version: version,
        ),
      );
    }
    network.flush(duplicateDeliveries: 1);
  }

  network
    ..reconnectAll()
    ..flush(duplicateDeliveries: 2);
  network.assertConverged();

  return <String, Object?>{
    'version': version,
    'replicaCount': network.replicaCount,
    'publishedUpdates': network.publishedUpdates,
    'appliedUpdates': network.appliedUpdates,
    'snapshotBytes': network.snapshotDigest.length,
  };
}

List<int> _insertUpdate({
  required int client,
  required String text,
  required int version,
}) {
  final doc = _docWithItem(client, text);
  return version == 1 ? encodeStateAsUpdate(doc) : encodeStateAsUpdateV2(doc);
}

List<int> _deleteUpdate({
  required int client,
  required int version,
}) {
  final doc = Doc(clientId: ClientId(8000 + client));
  doc.store.addPendingDeleteSet(
    IdSet()..add(_id(client, 0)),
  );
  return version == 1 ? encodeStateAsUpdate(doc) : encodeStateAsUpdateV2(doc);
}

final class _UpdateNetwork {
  _UpdateNetwork({
    required this.version,
    required this.random,
    required int replicaCount,
  })  : _replicas = List<Doc>.generate(
          replicaCount,
          (index) => Doc(clientId: ClientId(7000 + index)),
        ),
        _connected = List<List<bool>>.generate(
          replicaCount,
          (_) => List<bool>.filled(replicaCount, true),
        );

  final int version;
  final Random random;
  final List<Doc> _replicas;
  final List<List<bool>> _connected;
  final List<_PendingUpdate> _pending = <_PendingUpdate>[];
  int publishedUpdates = 0;
  int appliedUpdates = 0;

  int get replicaCount => _replicas.length;

  String get snapshotDigest => _snapshot(_replicas.first);

  void publish({required int origin, required List<int> update}) {
    _apply(_replicas[origin], update);
    for (var target = 0; target < _replicas.length; target += 1) {
      if (target != origin) {
        _pending.add(
          _PendingUpdate(origin: origin, target: target, update: update),
        );
      }
    }
    publishedUpdates += 1;
  }

  void flush({required int duplicateDeliveries}) {
    final blocked = <_PendingUpdate>[];
    final deliveries = <_PendingUpdate>[];
    for (final update in _pending) {
      if (_connected[update.origin][update.target]) {
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
    deliveries.shuffle(random);
    for (final delivery in deliveries) {
      _apply(_replicas[delivery.target], delivery.update);
    }
  }

  void toggleRandomLink() {
    final a = random.nextInt(_replicas.length);
    var b = random.nextInt(_replicas.length - 1);
    if (b >= a) {
      b += 1;
    }
    _connected[a][b] = !_connected[a][b];
    _connected[b][a] = _connected[a][b];
  }

  void reconnectAll() {
    for (var a = 0; a < _replicas.length; a += 1) {
      for (var b = 0; b < _replicas.length; b += 1) {
        _connected[a][b] = true;
      }
    }
  }

  void assertConverged() {
    _expect(_pending.isEmpty, 'all pending updates delivered');
    final expected = _snapshot(_replicas.first);
    for (var index = 1; index < _replicas.length; index += 1) {
      _expect(_snapshot(_replicas[index]) == expected, 'replica $index');
    }
  }

  void _apply(Doc doc, List<int> update) {
    version == 1 ? applyUpdate(doc, update) : applyUpdateV2(doc, update);
    appliedUpdates += 1;
  }

  String _snapshot(Doc doc) {
    return '${_rootText(doc)}|${_stateDigest(doc.store.stateVector())}';
  }
}

final class _PendingUpdate {
  const _PendingUpdate({
    required this.origin,
    required this.target,
    required this.update,
  });

  final int origin;
  final int target;
  final List<int> update;
}
