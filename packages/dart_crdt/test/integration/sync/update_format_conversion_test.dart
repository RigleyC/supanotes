import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_crdt/src/binary/any_value.dart';
import 'package:dart_crdt/src/content/content.dart';
import 'package:dart_crdt/src/doc/doc.dart';
import 'package:dart_crdt/src/structs/abstract_struct.dart';
import 'package:dart_crdt/src/structs/id.dart';
import 'package:dart_crdt/src/sync/apply_update.dart';
import 'package:dart_crdt/src/sync/state_update.dart';
import 'package:dart_crdt/src/sync/update_format.dart';
import 'package:test/test.dart';

void main() {
  group('update format conversion fixtures', () {
    test('converts a fixture V1 text update to V2 and back', () {
      final fixture = _readFixture('simple_text_v1.json');
      final v2 = convertUpdateFormatV1ToV2(fixture);
      final roundTrip = convertUpdateFormatV2ToV1(v2);
      final fromV2 = Doc(clientId: ClientId(9));
      final fromV1 = Doc(clientId: ClientId(10));

      applyUpdateV2(fromV2, v2);
      applyUpdate(fromV1, roundTrip);

      expect(_rootContents(fromV2), [ContentString('hi')]);
      expect(_rootContents(fromV1), [ContentString('hi')]);
      expect(fromV1.store.stateVector(), fromV2.store.stateVector());
    });
  });

  group('update format conversion content coverage', () {
    for (final scenario in _scenarios()) {
      test('round-trips ${scenario.name}', () {
        final v1 = encodeStateAsUpdate(_docWithContent(scenario.content));
        final v2 = convertUpdateFormatV1ToV2(v1);
        final roundTrip = convertUpdateFormatV2ToV1(v2);
        final converted = Doc(clientId: ClientId(9));

        applyUpdate(converted, roundTrip);

        expect(_rootContents(converted), [scenario.content]);
      });
    }

    test('preserves deletes across conversion', () {
      final doc = Doc(clientId: ClientId(1));
      doc.store.add(GC(id: _id(1, 0), length: 2));
      final converted = Doc(clientId: ClientId(9));

      applyUpdate(
        converted,
        convertUpdateFormatV2ToV1(
          convertUpdateFormatV1ToV2(encodeStateAsUpdate(doc)),
        ),
      );

      expect(converted.store.getClock(ClientId(1)), Clock(2));
      expect(converted.store.structsFor(ClientId(1)).single, isA<GC>());
    });
  });
}

List<int> _readFixture(String name) {
  final file = File('test/fixtures/compat/update_format/$name');
  final json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  return List<int>.unmodifiable((json['bytes'] as List<Object?>).cast<int>());
}

List<_Scenario> _scenarios() {
  return [
    _Scenario('arrays', ContentAny([JsonNumber(1), const JsonString('a')])),
    _Scenario(
      'maps',
      ContentJson([
        JsonMap({'k': const JsonString('v')}),
      ]),
    ),
    _Scenario('text', ContentString('hello')),
    _Scenario('formatting', ContentFormat(key: 'bold', value: true)),
    _Scenario(
      'nested types',
      ContentType(
        const SharedTypePlaceholder(kind: SharedTypeKind.text, name: 'body'),
      ),
    ),
    _Scenario('binary content', ContentBinary(Uint8List.fromList([1, 2, 3]))),
  ];
}

Doc _docWithContent(AbstractContent content) {
  final doc = Doc(clientId: ClientId(1));
  doc.store.add(
    Item(
      id: _id(1, 0),
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

Id _id(int client, int clock) {
  return Id(client: ClientId(client), clock: Clock(clock));
}

final class _Scenario {
  const _Scenario(this.name, this.content);

  final String name;
  final AbstractContent content;
}
