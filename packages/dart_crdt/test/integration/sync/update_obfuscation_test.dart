import 'dart:typed_data';

import 'package:dart_crdt/src/binary/any_value.dart';
import 'package:dart_crdt/src/content/content.dart';
import 'package:dart_crdt/src/doc/doc.dart';
import 'package:dart_crdt/src/structs/abstract_struct.dart';
import 'package:dart_crdt/src/structs/id.dart';
import 'package:dart_crdt/src/sync/apply_update.dart';
import 'package:dart_crdt/src/sync/state_update.dart';
import 'package:dart_crdt/src/sync/update_algebra.dart';
import 'package:dart_crdt/src/sync/update_obfuscation.dart';
import 'package:test/test.dart';

void main() {
  group('obfuscateUpdate', () {
    test('replaces text while preserving clocks and mergeability', () {
      final original =
          encodeStateAsUpdate(_docWithContent(1, ContentString('secret')));
      final other =
          encodeStateAsUpdate(_docWithContent(2, ContentString('public')));
      final obfuscated = obfuscateUpdate(original);
      final target = Doc(clientId: ClientId(9));

      applyUpdate(target, mergeUpdates([obfuscated, other]));

      expect(target.store.stateVector(), {
        ClientId(1): Clock(6),
        ClientId(2): Clock(6),
      });
      expect(
          _rootContents(target).whereType<ContentString>().map((c) => c.value),
          [
            'xxxxxx',
            'public',
          ]);
    });

    test('obfuscates scalar, collection, and binary payloads', () {
      final contents = [
        ContentAny([const JsonString('secret'), JsonNumber(7)]),
        ContentJson([
          JsonMap({'secret': const JsonBool(true)}),
        ]),
        ContentBinary(Uint8List.fromList([9, 8, 7])),
        ContentEmbed({'secret': true}),
      ];

      for (var index = 0; index < contents.length; index += 1) {
        final target = Doc(clientId: ClientId(9));
        applyUpdate(
          target,
          obfuscateUpdate(_updateFor(index + 1, contents[index])),
        );
        final content = _rootContents(target).single;

        switch (content) {
          case ContentAny(:final values):
            expect(values, [const JsonString('0'), const JsonString('0')]);
          case ContentJson(:final values):
            expect(values, [const JsonString('0')]);
          case ContentBinary(:final bytes):
            expect(bytes, [0, 0, 0]);
          case ContentEmbed(:final value):
            expect(value, const JsonString('0'));
          default:
            fail('unexpected content ${content.runtimeType}');
        }
      }
    });

    test('handles formatting, subdocument, and type names with options', () {
      final format = _roundTrip(
        ContentFormat(key: 'bold', value: true),
        options: const UpdateObfuscationOptions(preserveFormattingKeys: true),
      ) as ContentFormat;
      final type = _roundTrip(
        ContentType(
          const SharedTypePlaceholder(kind: SharedTypeKind.text, name: 'body'),
        ),
      ) as ContentType;
      final doc = _roundTrip(
        ContentDocument(guid: 'secret-doc', collectionId: 'team'),
      ) as ContentDocument;

      expect(format.key, 'bold');
      expect(format.value, const JsonString('0'));
      expect(type.sharedType.name, 'type');
      expect(doc.document.guid, 'doc');
      expect(doc.document.collectionId, 'collection');
    });
  });

  group('obfuscateUpdateV2', () {
    test('preserves V2 metadata and replaces content', () {
      final obfuscated = obfuscateUpdateV2(
        encodeStateAsUpdateV2(_docWithContent(1, ContentString('v2secret'))),
      );
      final target = Doc(clientId: ClientId(9));

      applyUpdateV2(target, obfuscated);

      expect(target.store.getClock(ClientId(1)), Clock(8));
      expect((_rootContents(target).single as ContentString).value, 'xxxxxxxx');
    });
  });
}

AbstractContent _roundTrip(
  AbstractContent content, {
  UpdateObfuscationOptions options = const UpdateObfuscationOptions(),
}) {
  final target = Doc(clientId: ClientId(9));
  applyUpdate(
    target,
    obfuscateUpdate(_updateFor(1, content), options: options),
  );
  return _rootContents(target).single;
}

List<int> _updateFor(int client, AbstractContent content) {
  return encodeStateAsUpdate(_docWithContent(client, content));
}

Doc _docWithContent(int client, AbstractContent content) {
  final doc = Doc(clientId: ClientId(client));
  doc.store.add(
    Item(
      id: Id(client: ClientId(client), clock: Clock(0)),
      parent: doc.itemParentForKey('root'),
      content: content,
    ),
  );
  return doc;
}

List<AbstractContent> _rootContents(Doc doc) {
  return [
    for (final item in doc.itemParentForKey('root').items())
      if (!item.deleted) item.content,
  ];
}
