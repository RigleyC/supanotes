import 'package:dart_crdt/src/binary/any_value.dart';
import 'package:dart_crdt/src/content/content.dart';
import 'package:dart_crdt/src/doc/doc.dart';
import 'package:dart_crdt/src/structs/abstract_struct.dart';
import 'package:dart_crdt/src/structs/id.dart';
import 'package:dart_crdt/src/sync/document_update_helpers.dart';
import 'package:dart_crdt/src/sync/state_update.dart';
import 'package:dart_crdt/src/sync/update_decoder.dart';
import 'package:test/test.dart';

void main() {
  group('document update helpers', () {
    test('creates an empty V1 document with propagated options', () {
      final options = DocOptions(
        guid: 'created',
        collectionId: 'team',
        meta: const JsonString('meta'),
        clientId: ClientId(9),
        autoLoad: true,
        gc: false,
      );

      final doc =
          createDocFromUpdate(encodeStateAsUpdate(Doc()), options: options);

      expect(doc.guid, 'created');
      expect(doc.collectionId, 'team');
      expect(doc.meta, const JsonString('meta'));
      expect(doc.clientId, ClientId(9));
      expect(doc.shouldLoad, isTrue);
      expect(doc.gc, isFalse);
      expect(doc.store.isEmpty, isTrue);
    });

    test('creates documents from V1 and V2 input', () {
      final source = _docWithItem('hello');
      final v1 = createDocFromUpdate(encodeStateAsUpdate(source));
      final v2 = createDocFromUpdateV2(encodeStateAsUpdateV2(source));

      expect(_rootText(v1), 'hello');
      expect(_rootText(v2), 'hello');
      expect(v1.store.stateVector(), v2.store.stateVector());
    });

    test('clones documents independently with explicit options', () {
      final source = _docWithItem('a');
      final clone = cloneDoc(
        source,
        options: DocOptions(guid: 'clone', clientId: ClientId(9)),
      );

      clone.store.add(
        Item(
          id: _id(2, 0),
          parent: clone.itemParentForKey('root'),
          content: ContentString('b'),
        ),
      );

      expect(clone.guid, 'clone');
      expect(_rootText(source), 'a');
      expect(_rootText(clone), 'ab');
      expect(source.store.getClock(ClientId(2)), Clock(0));
    });

    test('rejects invalid updates', () {
      expect(
        () => createDocFromUpdate(const [0, 0, 99]),
        throwsA(isA<MalformedUpdateException>()),
      );
      expect(
        () => createDocFromUpdateV2(const [1]),
        throwsA(isA<MalformedUpdateException>()),
      );
    });
  });
}

Doc _docWithItem(String text) {
  final doc = Doc(clientId: ClientId(1));
  doc.store.add(
    Item(
      id: _id(1, 0),
      parent: doc.itemParentForKey('root'),
      content: ContentString(text),
    ),
  );
  return doc;
}

String _rootText(Doc doc) {
  final linkedItems = doc.itemParentForKey('root').items();
  final items = <Item>[...linkedItems];
  for (final item in _storedRootItems(doc)) {
    if (!items.any((existing) => existing.id == item.id)) {
      items.add(item);
    }
  }
  return items
      .where((item) => !item.deleted)
      .map((item) => (item.content as ContentString).value)
      .join();
}

Id _id(int client, int clock) {
  return Id(client: ClientId(client), clock: Clock(clock));
}

List<Item> _storedRootItems(Doc doc) {
  return [
    for (final client in doc.store.clients)
      for (final struct in doc.store.structsFor(client))
        if (struct is Item && struct.parent?.key == 'root') struct,
  ];
}
