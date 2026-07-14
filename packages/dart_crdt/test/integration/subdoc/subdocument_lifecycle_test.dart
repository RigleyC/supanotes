import 'package:dart_crdt/dart_crdt.dart';
import 'package:test/test.dart';

void main() {
  group('subdocument lifecycle', () {
    test('records metadata, autoload, and parent transaction events', () {
      final doc = Doc(gc: false, clientId: ClientId(9));
      final transactions = <Transaction>[];
      final subdocEvents = <SubdocsEvent>[];
      doc.afterTransaction.add(transactions.add);
      doc.onSubdocs.add(subdocEvents.add);

      applyUpdate(
        doc,
        encodeStateAsUpdate(
          _sourceSubdoc(
            1,
            ContentDocument(
              guid: 'child',
              collectionId: 'team',
              meta: const JsonString('draft'),
              autoLoad: true,
            ),
          ),
        ),
      );

      final subdoc = doc.getSubdocs().single;
      expect(subdoc.guid, 'child');
      expect(subdoc.collectionId, 'team');
      expect(subdoc.meta, const JsonString('draft'));
      expect(subdoc.autoLoad, isTrue);
      expect(subdoc.shouldLoad, isTrue);
      expect(subdoc.isLoaded, isFalse);
      expect(transactions.single.subdocsAdded, {subdoc});
      expect(transactions.single.subdocsLoaded, {subdoc});
      expect(subdocEvents.single.added, {subdoc});
      expect(subdocEvents.single.loaded, {subdoc});
    });

    test('loads, syncs, destroys, and replaces through the parent doc',
        () async {
      final doc = Doc(gc: false, clientId: ClientId(9));
      final subdocEvents = <SubdocsEvent>[];
      doc.onSubdocs.add(subdocEvents.add);
      applyUpdate(
        doc,
        encodeStateAsUpdate(_sourceSubdoc(2, ContentDocument(guid: 'child'))),
      );
      final subdoc = doc.getSubdocs().single;
      final loaded = <Subdocument>[];
      final destroyed = <Subdocument>[];
      final syncStates = <bool>[];
      subdoc.onLoad.add(loaded.add);
      subdoc.onDestroy.add(destroyed.add);
      subdoc.onSync.add(syncStates.add);

      await subdoc.load();
      subdoc.setSynced(true);
      await subdoc.whenSynced;
      await subdoc.destroy();

      final replacement = doc.getSubdocs().single;
      expect(loaded, [subdoc]);
      expect(syncStates, [true, false]);
      expect(destroyed, [subdoc]);
      expect(subdoc.isDestroyed, isTrue);
      expect(replacement.guid, 'child');
      expect(identical(replacement, subdoc), isFalse);
      expect(replacement.isDestroyed, isFalse);
      expect(_rootDocument(doc).document, same(replacement));
      expect(subdocEvents.last.removed, {subdoc});
      expect(subdocEvents.last.added, {replacement});
    });

    test('supports document content in map attributes', () {
      final doc = Doc(gc: false, clientId: ClientId(9));

      applyUpdate(
        doc,
        encodeStateAsUpdate(
          _sourceSubdoc(
            3,
            ContentDocument(guid: 'mapped-child', shouldLoad: true),
            parent: 'attrs',
            parentSub: 'child',
          ),
        ),
      );

      final item = doc.itemParentForKey('attrs').currentFor('child');
      expect(item?.content, isA<ContentDocument>());
      expect(doc.getSubdocGuids(), {'mapped-child'});
      expect(doc.getSubdocs().single.shouldLoad, isTrue);
    });

    test('undo and redo remove and restore subdocuments', () {
      final doc = Doc(gc: false, clientId: ClientId(9));
      final manager = UndoManager(doc);

      applyUpdate(
        doc,
        encodeStateAsUpdate(
          _sourceSubdoc(4, ContentDocument(guid: 'undo-child')),
        ),
      );
      expect(doc.getSubdocGuids(), {'undo-child'});

      manager.undo();
      expect(doc.getSubdocGuids(), isEmpty);

      manager.redo();
      expect(doc.getSubdocGuids(), {'undo-child'});
    });
  });
}

Doc _sourceSubdoc(
  int client,
  ContentDocument content, {
  String parent = 'root',
  String? parentSub,
}) {
  final doc = Doc(gc: false, clientId: ClientId(client));
  doc.store.add(
    Item(
      id: Id(client: ClientId(client), clock: Clock(0)),
      parent: doc.itemParentForKey(parent),
      parentSub: parentSub,
      content: content,
    ),
  );
  return doc;
}

ContentDocument _rootDocument(Doc doc) {
  return doc
      .itemParentForKey('root')
      .items()
      .where((item) => !item.deleted)
      .map((item) => item.content)
      .whereType<ContentDocument>()
      .single;
}
