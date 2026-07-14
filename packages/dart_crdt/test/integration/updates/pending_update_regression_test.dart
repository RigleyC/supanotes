import 'package:dart_crdt/src/content/content.dart';
import 'package:dart_crdt/src/doc/doc.dart';
import 'package:dart_crdt/src/structs/abstract_struct.dart';
import 'package:dart_crdt/src/structs/id.dart';
import 'package:test/test.dart';

import '../../helpers/update_regression_helpers.dart';

void main() {
  group('pending update regressions', () {
    for (final version in updateVersions) {
      test('${version.name} retries pending structs after missing clocks', () {
        final target = Doc(clientId: ClientId(96));

        version.apply(target, version.fixture('pending_later'));

        expect(target.store.pendingStructUpdate, isNotNull);
        expect(target.store.pendingStructs.isNotEmpty, isTrue);
        expect(target.store.isEmpty, isTrue);

        version.apply(target, version.fixture('pending_base'));

        expect(target.store.pendingStructUpdate, isNull);
        expect(target.store.pendingStructs.isEmpty, isTrue);
        expect(target.store.getClock(ClientId(4)), Clock(3));
        expect(rootText(target), 'abc');
      });

      test('${version.name} retries pending delete sets after structs arrive',
          () {
        final target = Doc(clientId: ClientId(97));

        version.apply(target, version.fixture('delete_only'));

        expect(target.store.pendingDeleteSet.hasId(id(4, 1)), isTrue);

        version.apply(
          target,
          version.encode(docWithContent(4, [ContentString('ab')])),
        );

        final item = target.store.itemContaining(id(4, 1));
        expect(item, isA<Item>());
        expect(item!.deleted, isTrue);
        expect(target.store.pendingDeleteSet.isEmpty, isTrue);
      });
    }
  });
}
