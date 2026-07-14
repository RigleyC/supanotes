import 'package:dart_crdt/src/doc/doc.dart';
import 'package:dart_crdt/src/metadata/content_ids.dart';
import 'package:dart_crdt/src/structs/id.dart';
import 'package:test/test.dart';

import '../../helpers/update_regression_helpers.dart';

void main() {
  group('update intersection regressions', () {
    for (final version in updateVersions) {
      test('${version.name} extracts fixture insert and delete ids', () {
        final ids = version.contentIds(version.fixture('intersection_source'));

        expect(ids.inserts, idSet([(6, 0, 6)]));
        expect(ids.deletes, idSet([(6, 2, 2)]));
      });

      test('${version.name} intersects prefix inserts into applyable updates',
          () {
        final filtered = version.intersect(
          version.fixture('intersection_source'),
          ContentIds(inserts: idSet([(6, 0, 2)])),
        );
        final target = Doc(clientId: ClientId(100));

        expect(version.contentIds(filtered).inserts, idSet([(6, 0, 2)]));

        version.apply(target, filtered);

        expect(rootText(target), 'ab');
      });

      test('${version.name} intersects delete sets independently', () {
        final filtered = version.intersect(
          version.fixture('intersection_source'),
          ContentIds(deletes: idSet([(6, 3, 1)])),
        );
        final ids = version.contentIds(filtered);

        expect(ids.inserts.isEmpty, isTrue);
        expect(ids.deletes, idSet([(6, 3, 1)]));
      });
    }
  });
}
