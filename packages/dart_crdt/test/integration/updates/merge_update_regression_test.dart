import 'package:dart_crdt/src/content/content.dart';
import 'package:dart_crdt/src/doc/doc.dart';
import 'package:dart_crdt/src/structs/id.dart';
import 'package:dart_crdt/src/sync/state_vector.dart';
import 'package:test/test.dart';

import '../../helpers/update_regression_helpers.dart';

void main() {
  group('merge update regressions', () {
    for (final version in updateVersions) {
      test('${version.name} merges fixture updates idempotently', () {
        final a = version.fixture('merge_a');
        final b = version.fixture('merge_b');
        final forward = version.merge([a, b, a]);
        final reverse = version.merge([b, a, b]);
        final left = Doc(clientId: ClientId(90));
        final right = Doc(clientId: ClientId(91));

        version
          ..apply(left, forward)
          ..apply(right, reverse);

        expect(left.store.stateVector(), right.store.stateVector());
        expect(
            rootContents(left).whereType<ContentString>().map((c) => c.value), {
          'alpha',
          'bravo',
        });
        expect(rootText(left).length, 10);
      });

      test('${version.name} diffs merged updates against known state', () {
        final a = version.fixture('merge_a');
        final b = version.fixture('merge_b');
        final partial = Doc(clientId: ClientId(92));
        version.apply(partial, a);

        final merged = version.merge([a, b]);
        final diff = version.diff(merged, encodeDocumentStateVector(partial));
        version.apply(partial, diff);

        expect(partial.store.stateVector(), {
          ClientId(1): Clock(5),
          ClientId(2): Clock(5),
        });
        expect(rootText(partial).length, 10);
      });
    }
  });
}
