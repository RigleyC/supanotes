import 'package:dart_crdt/dart_crdt.dart';
import 'package:test/test.dart';

import '../../helpers/binary_sync_harness.dart';

/// M5 + M6: nested shared types (a type inside a map/array/text) are now live
/// and store-backed, so they serialize over the binary wire — exercising the
/// nested parent-id wire format and the detached->integrated prelim flush.
void main() {
  SharedType nested(Doc doc, String root, String key) {
    return doc.getMap(root).getAttr(key)! as SharedType;
  }

  group('nested types binary sync', () {
    test('a nested map created then mutated syncs to a peer', () {
      final a = Doc();
      final b = Doc();

      final child = SharedType(kind: SharedTypeKind.map);
      a.getMap('root').setAttr('child', child);
      child
        ..setAttr('k', 'v')
        ..setAttr('n', 42);
      applyUpdate(b, encodeStateAsUpdate(a));

      final bChild = nested(b, 'root', 'child');
      expect(bChild.kind, SharedTypeKind.map);
      expect(bChild.getAttr('k'), 'v');
      expect(bChild.getAttr('n'), 42);
    });

    test('detached nested type flushes its prelim content on integration', () {
      final a = Doc();
      final b = Doc();

      // Build a fully-populated detached map, THEN attach it.
      final child = SharedType(kind: SharedTypeKind.map)
        ..setAttr('title', 'Draft')
        ..setAttr('count', 3);
      a.getMap('root').setAttr('child', child);

      applyUpdate(b, encodeStateAsUpdate(a));
      final bChild = nested(b, 'root', 'child');
      expect(bChild.getAttrs(), {'title': 'Draft', 'count': 3});
    });

    test('a nested array inside a map syncs', () {
      final a = Doc();
      final b = Doc();

      final list = SharedType(kind: SharedTypeKind.array)
        ..insertAll(0, ['x', 'y']);
      a.getMap('root').setAttr('list', list);
      (a.getMap('root').getAttr('list')! as SharedType).push('z');

      applyUpdate(b, encodeStateAsUpdate(a));
      final bList = nested(b, 'root', 'list');
      expect(bList.toArray(), ['x', 'y', 'z']);
    });

    test('deep nesting (map -> array -> map) round-trips', () {
      final a = Doc();
      final b = Doc();

      final inner = SharedType(kind: SharedTypeKind.map)..setAttr('deep', true);
      final mid = SharedType(kind: SharedTypeKind.array)..insertAll(0, [inner]);
      a.getMap('root').setAttr('mid', mid);

      applyUpdate(b, encodeStateAsUpdate(a));
      final bMid = nested(b, 'root', 'mid');
      final bInner = bMid.get(0)! as SharedType;
      expect(bInner.getAttr('deep'), true);
    });

    test('mutating a synced nested type and syncing back converges', () {
      final a = Doc();
      final b = Doc();

      a.getMap('root').setAttr('child', SharedType(kind: SharedTypeKind.map));
      applyUpdate(b, encodeStateAsUpdate(a));

      // B edits the nested type it received, then sends the delta back to A.
      final bSv = encodeDocumentStateVector(b);
      nested(b, 'root', 'child').setAttr('fromB', 'hi');
      applyUpdate(a, encodeStateAsUpdate(b, encodeDocumentStateVector(a)));
      // And A's view, with B caught up too.
      applyUpdate(b, encodeStateAsUpdate(a, bSv));

      expect(nested(a, 'root', 'child').getAttr('fromB'), 'hi');
      expect(nested(b, 'root', 'child').getAttr('fromB'), 'hi');
    });

    test('nested types converge across a partitioned harness', () {
      String snap(Doc doc) {
        final child = doc.getMap('root').getAttr('child');
        if (child is! SharedType) return '<none>';
        final keys = child.attrKeys.toList()..sort();
        return keys.map((k) => '$k=${child.getAttr(k)}').join('|');
      }

      final harness =
          BinarySyncHarness(replicaCount: 3, snapshot: snap, seed: 4);
      harness.mutate(0, (doc) {
        doc
            .getMap('root')
            .setAttr('child', SharedType(kind: SharedTypeKind.map));
      });
      harness.flush();

      harness.disconnect(0, 1);
      harness.mutate(0, (doc) {
        (doc.getMap('root').getAttr('child')! as SharedType).setAttr('a', 1);
      });
      harness.mutate(1, (doc) {
        (doc.getMap('root').getAttr('child')! as SharedType).setAttr('b', 2);
      });
      harness.flush(duplicateDeliveries: 1);
      harness.reconnectAll();
      harness.reconcileAll();

      harness.assertConverged();
      final child =
          harness.replicaAt(2).getMap('root').getAttr('child')! as SharedType;
      expect(child.getAttrs(), {'a': 1, 'b': 2});
    });
  });
}
