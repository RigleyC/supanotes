import 'package:dart_crdt/src/content/content.dart';
import 'package:dart_crdt/src/doc/doc.dart';
import 'package:dart_crdt/src/structs/id.dart';
import 'package:test/test.dart';

import '../../helpers/update_regression_helpers.dart';

void main() {
  group('update key encoding regressions', () {
    for (final version in updateVersions) {
      test('${version.name} applies repeated-key formatting fixture content',
          () {
        final target = Doc(clientId: ClientId(93));
        final update = version.fixture('format_keys');

        version.apply(target, update);

        final contents = rootContents(target);
        expect(
          contents.whereType<ContentString>().map((c) => c.value),
          unorderedEquals([
            'A',
            'B',
          ]),
        );
        expect(
          contents.whereType<ContentFormat>().map((c) => c.key).toSet(),
          {
            'bold',
            'color',
          },
        );
      });
    }

    test('V2 writes repeated format keys through the key cache', () {
      const encodedBold = [4, 98, 111, 108, 100];
      final v1 = updateFixture('format_keys', 'v1');
      final v2 = updateFixture('format_keys', 'v2');

      expect(countBytePattern(v1, encodedBold), 3);
      expect(countBytePattern(v2, encodedBold), 1);
    });
  });
}
