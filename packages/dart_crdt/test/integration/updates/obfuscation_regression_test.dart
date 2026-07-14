import 'package:dart_crdt/src/binary/any_value.dart';
import 'package:dart_crdt/src/content/content.dart';
import 'package:dart_crdt/src/doc/doc.dart';
import 'package:dart_crdt/src/structs/id.dart';
import 'package:dart_crdt/src/sync/update_obfuscation.dart';
import 'package:test/test.dart';

import '../../helpers/update_regression_helpers.dart';

void main() {
  group('update obfuscation regressions', () {
    for (final version in updateVersions) {
      test('${version.name} obfuscates fixture content by content type', () {
        final target = Doc(clientId: ClientId(98));

        version.apply(
          target,
          version.obfuscate(version.fixture('obfuscation_source')),
        );

        final contents = rootContents(target);
        final format = contents.whereType<ContentFormat>().single;
        final document = contents.whereType<ContentDocument>().single;
        expect(contents.whereType<ContentString>().single.value, 'xxxxxx');
        expect(format.key, 'format');
        expect(format.value, const JsonString('0'));
        expect(contents.whereType<ContentBinary>().single.bytes, [0, 0]);
        expect(
          contents.whereType<ContentEmbed>().single.value,
          const JsonString('0'),
        );
        expect(
          contents.whereType<ContentType>().single.sharedType.name,
          'type',
        );
        expect(document.document.guid, 'doc');
        expect(
          document.document.collectionId,
          'collection',
        );
      });

      test('${version.name} preserves selected diagnostic names by option', () {
        final target = Doc(clientId: ClientId(99));

        version.apply(
          target,
          version.obfuscate(
            version.fixture('obfuscation_source'),
            options: const UpdateObfuscationOptions(
              preserveFormattingKeys: true,
              preserveSubdocumentGuids: true,
              preserveTypeNames: true,
            ),
          ),
        );

        final contents = rootContents(target);
        expect(contents.whereType<ContentFormat>().single.key, 'author');
        expect(
          contents.whereType<ContentType>().single.sharedType.name,
          'body',
        );
        expect(
          contents.whereType<ContentDocument>().single.document.guid,
          'subdoc',
        );
      });
    }
  });
}
