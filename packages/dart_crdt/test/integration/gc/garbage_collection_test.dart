import 'package:dart_crdt/dart_crdt.dart';
import 'package:test/test.dart' hide Skip;

void main() {
  group('garbage collection and compaction', () {
    test('replaces deleted item content when enabled', () {
      final doc = Doc();

      applyUpdate(
        doc,
        encodeStateAsUpdate(_sourceText(1, 'abc', deleted: true)),
      );

      final item = _item(doc, 1);
      expect(item.deleted, isTrue);
      expect(item.content, isA<ContentDeleted>());
      expect(item.length, 3);
    });

    test('preserves deleted content when disabled or filtered', () {
      final disabled = Doc(gc: false);
      final filtered = Doc(gcFilter: (_) => false);

      applyUpdate(
        disabled,
        encodeStateAsUpdate(_sourceText(1, 'abc', deleted: true)),
      );
      applyUpdate(
        filtered,
        encodeStateAsUpdate(_sourceText(2, 'xyz', deleted: true)),
      );

      expect(_item(disabled, 1).content, isA<ContentString>());
      expect(_item(filtered, 2).content, isA<ContentString>());
    });

    test('keeps undo-managed deletes restorable', () {
      final doc = Doc(clientId: ClientId(9));
      final manager = UndoManager(doc);
      applyUpdate(doc, encodeStateAsUpdate(_sourceText(1, 'abc')));
      manager.stopCapturing();

      applyUpdate(
        doc,
        encodeStateAsUpdate(_sourceText(1, 'abc', deleted: true)),
      );

      final deleted = _item(doc, 1);
      expect(deleted.keep, isTrue);
      expect(deleted.content, isA<ContentString>());

      manager.undo();
      expect(_text(doc), 'abc');
    });

    test('handles nested deleted content and parentless tombstones', () {
      final nested = Doc();
      applyUpdate(
        nested,
        encodeStateAsUpdate(
          _sourceContent(
            3,
            ContentType(
              const SharedTypePlaceholder(
                kind: SharedTypeKind.xmlElement,
                name: 'node',
              ),
            ),
            deleted: true,
          ),
        ),
      );

      expect(_item(nested, 3).content, isA<ContentDeleted>());

      final parentless = Doc();
      applyUpdate(parentless, encodeStateAsUpdate(_sourceGc(4, 4)));
      expect(parentless.store.structsFor(ClientId(4)).single, isA<GC>());
    });

    test('merges adjacent deleted structs after delete-set application', () {
      final doc = Doc();
      var countBeforeCleanup = 0;
      doc.afterTransaction.add((_) {
        countBeforeCleanup = _structCount(doc);
      });

      applyUpdate(doc, encodeStateAsUpdate(_sourceTwoDeletedText()));

      final structs = doc.store.structsFor(ClientId(5));
      expect(countBeforeCleanup, 2);
      expect(structs, hasLength(1));
      expect(structs.single, isA<Item>());
      expect(structs.single.length, 2);
      expect((structs.single as Item).content, isA<ContentDeleted>());
    });

    test('rejects snapshot restore from GC-enabled documents', () {
      final doc = Doc();

      expect(
        () => createDocFromSnapshot(doc, snapshot(doc)),
        throwsA(isA<SnapshotRestoreException>()),
      );
    });
  });
}

Doc _sourceText(int client, String text, {bool deleted = false}) {
  return _sourceContent(client, ContentString(text), deleted: deleted);
}

Doc _sourceContent(
  int client,
  AbstractContent content, {
  bool deleted = false,
}) {
  final doc = Doc(gc: false, clientId: ClientId(client));
  final item = Item(
    id: Id(client: ClientId(client), clock: Clock(0)),
    parent: doc.itemParentForKey('root'),
    content: content,
  );
  if (deleted) {
    item.markDeleted();
  }
  doc.store.add(item);
  return doc;
}

Doc _sourceGc(int client, int length) {
  final doc = Doc(gc: false, clientId: ClientId(client));
  doc.store.add(
    GC(id: Id(client: ClientId(client), clock: Clock(0)), length: length),
  );
  return doc;
}

Doc _sourceTwoDeletedText() {
  final doc = Doc(gc: false, clientId: ClientId(5));
  final parent = doc.itemParentForKey('root');
  doc.store
    ..add(
      Item(
        id: Id(client: ClientId(5), clock: Clock(0)),
        parent: parent,
        content: ContentString('a'),
      )..markDeleted(),
    )
    ..add(
      Item(
        id: Id(client: ClientId(5), clock: Clock(1)),
        origin: Id(client: ClientId(5), clock: Clock(0)),
        parent: parent,
        content: ContentString('b'),
      )..markDeleted(),
    );
  return doc;
}

Item _item(Doc doc, int client) {
  return doc.store.structsFor(ClientId(client)).single as Item;
}

String _text(Doc doc) {
  return doc
      .itemParentForKey('root')
      .items()
      .where((item) => !item.deleted)
      .map((item) => item.content)
      .whereType<ContentString>()
      .map((content) => content.value)
      .join();
}

int _structCount(Doc doc) {
  return doc.store.clients
      .map((client) => doc.store.structsFor(client).length)
      .fold(0, (left, right) => left + right);
}
