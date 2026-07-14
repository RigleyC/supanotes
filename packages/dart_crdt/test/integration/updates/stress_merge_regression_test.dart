import 'package:dart_crdt/src/content/content.dart';
import 'package:dart_crdt/src/doc/doc.dart';
import 'package:dart_crdt/src/structs/id.dart';
import 'package:dart_crdt/src/sync/state_vector.dart';
import 'package:test/test.dart';

import '../../helpers/update_regression_helpers.dart';

void main() {
  group('stress merge update regressions', () {
    for (final version in updateVersions) {
      test('${version.name} merges many duplicate client updates', () {
        final updates = [
          for (var index = 0; index < 24; index += 1)
            version.encode(
              docWithContent(20 + index, [ContentString('t$index')]),
            ),
        ];
        final merged = version.merge([
          ...updates,
          ...updates.reversed,
          ...updates.whereIndexed((index, _) => index.isEven),
        ]);
        final target = Doc(clientId: ClientId(94));

        version.apply(target, merged);

        expect(target.store.stateVector(), {
          for (var index = 0; index < 24; index += 1)
            ClientId(20 + index): Clock('t$index'.length),
        });
        expect(rootContents(target), hasLength(24));
      });

      test('${version.name} stress diffs merged updates after partial sync',
          () {
        final updates = [
          for (var index = 0; index < 16; index += 1)
            version.encode(
              docWithContent(60 + index, [ContentString('s$index')]),
            ),
        ];
        final partial = Doc(clientId: ClientId(95));
        for (final update in updates.take(8)) {
          version.apply(partial, update);
        }

        final diff = version.diff(
          version.merge(updates),
          encodeDocumentStateVector(partial),
        );
        version.apply(partial, diff);

        expect(partial.store.clients, [
          for (var index = 60; index < 76; index += 1) ClientId(index),
        ]);
      });
    }
  });
}

extension _IndexedIterable<T> on Iterable<T> {
  Iterable<T> whereIndexed(bool Function(int index, T value) test) sync* {
    var index = 0;
    for (final value in this) {
      if (test(index, value)) {
        yield value;
      }
      index += 1;
    }
  }
}
