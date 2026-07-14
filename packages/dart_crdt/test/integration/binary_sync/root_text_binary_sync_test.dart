import 'package:dart_crdt/dart_crdt.dart';
import 'package:test/test.dart';

import '../../helpers/binary_sync_harness.dart';

/// M0: prove the binary-sync harness against the ALREADY-working root-text
/// store path. Root text serializes over `encodeStateAsUpdate`/`applyUpdate`
/// today, so these must pass now; if they don't, the harness is wrong (not the
/// production code). This locks in the verification backbone for M2+ (maps,
/// arrays, nested types), which do NOT sync today.
void main() {
  String text(Doc doc) => doc.getText('t').toPlainText();

  group('root text binary sync (M0 harness self-check)', () {
    test('a single edit propagates to every replica', () {
      final harness = BinarySyncHarness(
        replicaCount: 3,
        snapshot: text,
      );

      harness.mutate(0, (doc) => doc.getText('t').insertText(0, 'hello'));
      harness.flush();

      harness.assertConverged();
      expect(text(harness.replicaAt(1)), 'hello');
      expect(text(harness.replicaAt(2)), 'hello');
    });

    test('concurrent edits across a partition converge after reconcile', () {
      final harness = BinarySyncHarness(
        replicaCount: 3,
        snapshot: text,
        seed: 7,
      );

      // Everyone starts from a shared base.
      harness.mutate(0, (doc) => doc.getText('t').insertText(0, 'base'));
      harness.flush();
      expect(text(harness.replicaAt(2)), 'base');

      // Partition 0 from 1, edit concurrently on both sides.
      harness.disconnect(0, 1);
      harness.mutate(0, (doc) => doc.getText('t').insertText(4, '-zero'));
      harness.mutate(1, (doc) => doc.getText('t').insertText(0, 'one-'));
      harness.flush(duplicateDeliveries: 1);

      // Heal the partition and converge.
      harness.reconnectAll();
      harness.flush(duplicateDeliveries: 1);
      harness.reconcileAll();

      harness.assertConverged();
      final merged = text(harness.replicaAt(0));
      // Both concurrent inserts survive; CRDT picks a deterministic interleave.
      expect(merged.contains('one-'), isTrue, reason: merged);
      expect(merged.contains('-zero'), isTrue, reason: merged);
      expect(merged.contains('base'), isTrue, reason: merged);
      expect(merged.length, 'base'.length + '-zero'.length + 'one-'.length);
    });

    test('a replica that missed all traffic catches up via reconcile', () {
      final harness = BinarySyncHarness(
        replicaCount: 3,
        snapshot: text,
        seed: 13,
      );

      // Replica 2 is isolated the whole time.
      harness.disconnect(2, 0);
      harness.disconnect(2, 1);

      harness.mutate(0, (doc) => doc.getText('t').insertText(0, 'abc'));
      harness.mutate(1, (doc) => doc.getText('t').insertText(0, 'xyz'));
      harness.flush();
      expect(text(harness.replicaAt(2)), isEmpty);

      // Reconnect the straggler and let anti-entropy catch it up.
      harness.reconnectAll();
      harness.reconcileAll();

      harness.assertConverged();
      expect(text(harness.replicaAt(2)).length, 6);
    });

    test('converges over the V2 wire format too', () {
      final harness = BinarySyncHarness(
        replicaCount: 2,
        snapshot: text,
        seed: 21,
        useV2: true,
      );

      harness.mutate(0, (doc) => doc.getText('t').insertText(0, 'vee-two'));
      harness.mutate(1, (doc) => doc.getText('t').insertText(0, 'PRE-'));
      harness.flush(duplicateDeliveries: 2);
      harness.reconcileAll();

      harness.assertConverged();
      expect(
        text(harness.replicaAt(0)).length,
        'vee-two'.length + 'PRE-'.length,
      );
    });
  });
}
