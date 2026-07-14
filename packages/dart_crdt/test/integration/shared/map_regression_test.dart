import 'package:dart_crdt/src/content/content.dart';
import 'package:dart_crdt/src/doc/doc.dart';
import 'package:test/test.dart';

import '../../helpers/binary_sync_harness.dart';

void main() {
  group('shared map regressions', () {
    test('preserves event values through conflicts, iteration, and nesting',
        () {
      final doc = Doc();
      final map = doc.get('attrs');
      final child = SharedType(kind: SharedTypeKind.map, name: 'child');
      final events = <String>[];
      final deepEvents = <String>[];

      map
        ..observe((event) {
          for (final key in event.keys) {
            events.add('$key=${event.target.getAttr('$key')}');
          }
        })
        ..observeDeep((event) {
          deepEvents.add('${event.target.name}:${event.keys.join(',')}');
        });

      // Integrated root maps resolve conflicts structurally (last write wins),
      // not by the in-memory `clock:` argument.
      doc.transact((_) {
        map
          ..setAttr('title', 'old')
          ..setAttr('title', 'new')
          ..setAttr('child', child);
        child.setAttr('nested', 'value');
      });

      expect(map.getAttr('title'), 'new');
      expect(child.doc, same(doc));
      expect(child.parent, same(map));
      expect(map.attrEntries.map((entry) => entry.key).toList(), [
        'title',
        'child',
      ]);
      expect(events, [
        'title=new',
        'child=map:child',
      ]);
      expect(deepEvents, contains('child:nested'));

      map.clearAttrs();

      expect(child.parent, isNull);
      expect(map.attrSize, 0);
    });

    test('converges key conflicts across a partition and late binary sync', () {
      String snap(Doc doc) {
        final map = doc.getMap('attrs');
        final keys = map.attrKeys.toList()..sort();
        return keys.map((k) => '$k=${map.getAttr(k)}').join('|');
      }

      final harness = BinarySyncHarness(
        replicaCount: 3,
        snapshot: snap,
        seed: 202,
      );

      // A late update produced while replica 1 is disconnected.
      harness.disconnect(0, 1);
      harness.mutate(
        0,
        (doc) => doc.getMap('attrs').setAttr('late', 'value-0'),
      );
      harness.flush(duplicateDeliveries: 1);
      expect(harness.replicaAt(1).getMap('attrs').hasAttr('late'), isFalse);

      // Concurrent conflicting writes to the same key on both sides.
      harness.mutate(0, (doc) => doc.getMap('attrs').setAttr('k', 'zero'));
      harness.mutate(1, (doc) => doc.getMap('attrs').setAttr('k', 'one'));
      harness.mutate(2, (doc) => doc.getMap('attrs').setAttr('only2', 'v2'));
      harness.flush(duplicateDeliveries: 2);

      harness.reconnectAll();
      harness.flush(duplicateDeliveries: 2);
      harness.reconcileAll();

      harness.assertConverged();
      final merged = harness.replicaAt(1).getMap('attrs');
      expect(merged.getAttr('late'), 'value-0');
      expect(merged.getAttr('only2'), 'v2');
      expect(merged.getAttr('k'), anyOf('zero', 'one'));
      // The winner is identical on every replica.
      final winner = harness.replicaAt(0).getMap('attrs').getAttr('k');
      expect(harness.replicaAt(2).getMap('attrs').getAttr('k'), winner);
    });
  });
}
