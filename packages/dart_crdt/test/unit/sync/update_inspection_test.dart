import 'package:dart_crdt/src/content/content.dart';
import 'package:dart_crdt/src/doc/doc.dart';
import 'package:dart_crdt/src/metadata/id_set.dart';
import 'package:dart_crdt/src/structs/abstract_struct.dart';
import 'package:dart_crdt/src/structs/id.dart';
import 'package:dart_crdt/src/sync/state_update.dart';
import 'package:dart_crdt/src/sync/update_decoder.dart';
import 'package:dart_crdt/src/sync/update_inspection.dart';
import 'package:test/test.dart' hide Skip;

void main() {
  group('update inspection', () {
    test('decodes empty updates', () {
      final decoded = decodeUpdate(encodeStateAsUpdate(Doc()));

      expect(decoded.version, 1);
      expect(decoded.structs, isEmpty);
      expect(decoded.deleteSet.isEmpty, isTrue);
      expect(decoded.hasPendingStructs, isFalse);
      expect(logUpdate(encodeStateAsUpdate(Doc())), contains('structs: empty'));
    });

    test('summarizes mixed structs and delete sets', () {
      final doc = Doc(clientId: ClientId(1));
      doc.store
        ..add(_item(2, 'hi'))
        ..add(GC(id: _id(1, 0), length: 2));

      final decoded = decodeUpdate(encodeStateAsUpdate(doc));

      expect(decoded.structs.map((struct) => struct.kind), [
        'GC',
        'Item:ContentString',
      ]);
      expect(decoded.deleteSet.hasId(_id(1, 1)), isTrue);
      expect(logUpdate(encodeStateAsUpdate(doc)), contains('deleteSet: 1:'));
    });

    test('summarizes pending delete-only updates', () {
      final doc = Doc(clientId: ClientId(1))
        ..store.addPendingDeleteSet(IdSet()..add(_id(4, 1), length: 2));

      final decoded = decodeUpdate(encodeStateAsUpdate(doc));

      expect(decoded.structs, isEmpty);
      expect(decoded.deleteSet.hasId(_id(4, 2)), isTrue);
    });

    test('decodes V2 updates with deterministic debug text', () {
      final decoded = decodeUpdateV2(encodeStateAsUpdateV2(_docWithItem('v2')));
      final log = logUpdateV2(encodeStateAsUpdateV2(_docWithItem('v2')));

      expect(decoded.version, 2);
      expect(decoded.structs.single.kind, 'Item:ContentString');
      expect(log, contains('update-v2'));
      expect(log, contains('kind=Item:ContentString'));
    });

    test('rejects malformed input', () {
      expect(
        () => decodeUpdate(const [0, 0, 99]),
        throwsA(isA<MalformedUpdateException>()),
      );
    });
  });
}

Doc _docWithItem(String text) {
  final doc = Doc(clientId: ClientId(1));
  doc.store.add(_item(1, text));
  return doc;
}

Item _item(int client, String text) {
  return Item(
    id: _id(client, 0),
    parent: ItemParent(key: 'root'),
    content: ContentString(text),
  );
}

Id _id(int client, int clock) {
  return Id(client: ClientId(client), clock: Clock(clock));
}
