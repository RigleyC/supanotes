import 'package:dart_crdt/src/content/content.dart';
import 'package:dart_crdt/src/delta/delta_operation.dart';
import 'package:dart_crdt/src/doc/doc.dart';
import 'package:dart_crdt/src/structs/id.dart';
import 'package:dart_crdt/src/sync/apply_update.dart';
import 'package:dart_crdt/src/sync/state_update.dart';
import 'package:test/test.dart';

import '../../helpers/random_convergence_harness.dart';
import '../../helpers/random_shared_type_operations.dart';
import '../../helpers/shared_regression_fixture.dart';

void main() {
  group('shared text regressions', () {
    test('round-trips high-level insertText through binary updates', () {
      final source = Doc(clientId: ClientId(1));
      final text = source.getText('body')..insertText(0, 'Hello');

      final update = encodeStateAsUpdate(source);
      final v1Target = Doc(clientId: ClientId(2));
      applyUpdate(v1Target, update);

      final v2Target = Doc(clientId: ClientId(3));
      applyUpdateV2(v2Target, encodeStateAsUpdateV2(source));

      expect(update.length, greaterThan(2));
      expect(text.toPlainText(), 'Hello');
      expect(v1Target.getText('body').toPlainText(), 'Hello');
      expect(v1Target.getText('body').length, 5);
      expect(v2Target.getText('body').toPlainText(), 'Hello');
    });

    test('converges concurrent high-level text inserts through updates', () {
      final a = Doc(clientId: ClientId(1), gc: false);
      final ta = a.getText('body')..insertText(0, 'ABC');
      final b = Doc(clientId: ClientId(2), gc: false);
      applyUpdate(b, encodeStateAsUpdate(a));
      final tb = b.getText('body');

      ta.insertText(3, 'X');
      tb.insertText(0, 'Y');

      applyUpdate(b, encodeStateAsUpdate(a));
      applyUpdate(a, encodeStateAsUpdate(b));

      expect(ta.toPlainText(), tb.toPlainText());
      expect(ta.toPlainText(), contains('ABC'));
      expect(ta.toPlainText(), contains('X'));
      expect(ta.toPlainText(), contains('Y'));
    });

    test('round-trips middle inserts and deletes from high-level text', () {
      final source = Doc(clientId: ClientId(1), gc: false);
      final text = source.getText('body')
        ..insertText(0, 'AC')
        ..insertText(1, 'B');

      final inserted = Doc(clientId: ClientId(2), gc: false);
      applyUpdate(inserted, encodeStateAsUpdate(source));
      expect(inserted.getText('body').toPlainText(), 'ABC');

      text.deleteText(1, 1);
      final deleted = Doc(clientId: ClientId(3), gc: false);
      applyUpdate(deleted, encodeStateAsUpdate(source));
      expect(deleted.getText('body').toPlainText(), 'AC');
    });

    test('keeps formatting stable across fragmented edits', () {
      final doc = Doc();
      final text = doc.get('body', SharedTypeKind.text);
      final events = <Set<Object?>>[];
      text.observe((event) => events.add(event.keys));

      for (var index = 0; index < 64; index += 1) {
        text.insertText(
          index,
          index.isEven ? 'a' : 'b',
          attributes: DeltaAttributes.fromJson({'token': index}),
        );
      }
      text
        ..format(10, 20, DeltaAttributes.fromJson({'bold': true}))
        ..format(15, 5, DeltaAttributes.fromJson({'bold': null}))
        ..deleteText(30, 10)
        ..insertEmbed(
          30,
          {'image': 'asset'},
          attributes: DeltaAttributes.fromJson({'origin': 'fixture'}),
        );

      final delta = text.toDelta().toJson();

      expect(text.length, 55);
      expect(text.toPlainText().contains('\uFFFC'), isTrue);
      expect(delta.toString(), contains('token'));
      expect(delta.toString(), contains('origin'));
      expect(delta.toString(), contains('bold'));
      expect(events.length, greaterThan(60));
      expect(text.searchMarkers.single.index, 30);
    });

    test('preserves attribution-style attributes through fixture convergence',
        () {
      final scenario = sharedRegressionScenario('text');
      final harness = RandomConvergenceHarness<Doc>(
        seed: scenario.seed,
        replicaCount: scenario.replicaCount,
        createReplica: (_) => Doc(),
        snapshot: textConvergenceSnapshot,
        testFile: 'test/integration/shared/text_regression_test.dart',
        plainName: 'attribution-style attributes',
      );

      harness
        ..disconnect(0, 1)
        ..publish(
          originIndex: 0,
          operation: textInsertOperation(token: 888, origin: 0),
        )
        ..flushPending(duplicateDeliveries: scenario.duplicateDeliveries);

      expect(harness.pendingUpdateCount, greaterThan(0));

      harness.run(
        operationCount: scenario.operationCount,
        nextOperation: randomTextOperations(),
        networkChurnEvery: scenario.networkChurnEvery,
        duplicateDeliveries: scenario.duplicateDeliveries,
      );

      final uniqueSnapshots =
          harness.replicas.map(textConvergenceSnapshot).toSet();
      expect(uniqueSnapshots, hasLength(1));
      expect(uniqueSnapshots.single, contains('"token":888'));
      expect(uniqueSnapshots.single, contains('"origin":0'));
      expect(_traceContains(harness, 'text delete'), isTrue);
      expect(_traceContains(harness, 'duplicate'), isTrue);
    });
  });
}

bool _traceContains(RandomConvergenceHarness<Doc> harness, String text) {
  return harness.trace.any((entry) => entry.contains(text));
}
