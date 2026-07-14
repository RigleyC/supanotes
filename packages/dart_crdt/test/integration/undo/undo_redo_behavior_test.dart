import 'package:dart_crdt/dart_crdt.dart';
import 'package:test/test.dart';

void main() {
  group('UndoManager undo/redo behavior', () {
    test('undoes and redoes inserted text content with stack events', () {
      final doc = Doc(gc: false, clientId: ClientId(9));
      final manager = UndoManager(doc);
      final popped = <StackItemEvent>[];
      manager.stackItemPopped.add(popped.add);

      applyUpdate(doc, encodeStateAsUpdate(_sourceText(1, 'abc')));

      expect(_text(doc), 'abc');
      expect(manager.undo(), isNotNull);
      expect(_text(doc), isEmpty);
      expect(manager.canRedo(), isTrue);
      expect(popped.single.type, StackItemEventType.undo);

      expect(manager.redo(), isNotNull);
      expect(_text(doc), 'abc');
      expect(manager.canUndo(), isTrue);
    });

    test('restores deleted content and preserves stack metadata', () {
      final doc = Doc(gc: false, clientId: ClientId(9));
      final manager = UndoManager(doc);
      applyUpdate(doc, encodeStateAsUpdate(_sourceText(1, 'abc')));
      manager.stopCapturing();
      applyUpdate(
        doc,
        _deleteOnlyUpdate(_sourceText(1, 'abc', deleted: true), 1, 3),
      );
      manager.undoStack.last.meta['label'] = 'delete';

      final undone = manager.undo();
      expect(_text(doc), 'abc');
      expect(undone!.meta['label'], 'delete');

      manager.redo();
      expect(_text(doc), isEmpty);
    });

    test('handles map, tree placeholder, nested document, and redo', () {
      final doc = Doc(gc: false, clientId: ClientId(9));
      final manager = UndoManager(doc);
      applyUpdate(doc, encodeStateAsUpdate(_sourceMapValue(1, 'title', 'one')));
      applyUpdate(doc, encodeStateAsUpdate(_sourceXmlPlaceholder(2)));
      applyUpdate(doc, encodeStateAsUpdate(_sourceSubdoc(3)));

      expect(_mapText(doc, 'title'), 'one');
      expect(_rootContents(doc).whereType<ContentType>(), isNotEmpty);
      expect(doc.getSubdocGuids(), contains('child-doc'));

      manager.undo();
      expect(_mapText(doc, 'title'), isNull);
      expect(_rootContents(doc), isEmpty);
      expect(doc.getSubdocGuids(), isEmpty);

      manager.redo();
      expect(_mapText(doc, 'title'), 'one');
      expect(_rootContents(doc).whereType<ContentType>(), isNotEmpty);
      expect(doc.getSubdocGuids(), contains('child-doc'));
    });

    test('does not overwrite remote map conflicts while undoing local input',
        () {
      final doc = Doc(gc: false, clientId: ClientId(9));
      final manager = UndoManager(doc, trackedOrigins: {'local'});

      applyUpdate(
        doc,
        encodeStateAsUpdate(_sourceMapValue(1, 'title', 'local')),
        origin: 'local',
      );
      applyUpdate(
        doc,
        encodeStateAsUpdate(_sourceMapValue(2, 'title', 'remote')),
        origin: 'remote',
      );

      manager.undo();
      expect(_mapText(doc, 'title'), 'remote');
    });

    test('honors delete filters and undoContentIds selections', () {
      final filteredDoc = Doc(gc: false, clientId: ClientId(9));
      final filtered = UndoManager(filteredDoc, deleteFilter: (_) => false);
      applyUpdate(filteredDoc, encodeStateAsUpdate(_sourceText(1, 'x')));

      expect(filtered.undo(), isNull);
      expect(_text(filteredDoc), 'x');

      final selectedDoc = Doc(gc: false, clientId: ClientId(9));
      applyUpdate(selectedDoc, encodeStateAsUpdate(_sourceText(1, 'uv')));
      final selected = ContentIds(
        inserts: IdSet()
          ..addRange(ClientId(1), IdRange(start: Clock(0), length: 2)),
      );

      expect(undoContentIds(selectedDoc, selected), isNotNull);
      expect(_text(selectedDoc), isEmpty);
    });
  });
}

Doc _sourceText(int client, String text, {bool deleted = false}) {
  final doc = Doc(gc: false, clientId: ClientId(client));
  final item = _item(doc, client, ContentString(text));
  if (deleted) {
    item.markDeleted();
  }
  doc.store.add(item);
  return doc;
}

Doc _sourceMapValue(int client, String key, String value) {
  final doc = Doc(gc: false, clientId: ClientId(client));
  doc.store.add(
    _item(doc, client, ContentString(value), parent: 'attrs', parentSub: key),
  );
  return doc;
}

Doc _sourceXmlPlaceholder(int client) {
  final doc = Doc(gc: false, clientId: ClientId(client));
  doc.store.add(
    _item(
      doc,
      client,
      ContentType(
        const SharedTypePlaceholder(
          kind: SharedTypeKind.xmlElement,
          name: 'node',
        ),
      ),
    ),
  );
  return doc;
}

Doc _sourceSubdoc(int client) {
  final doc = Doc(gc: false, clientId: ClientId(client));
  doc.store.add(_item(doc, client, ContentDocument(guid: 'child-doc')));
  return doc;
}

List<int> _deleteOnlyUpdate(Doc doc, int client, int clock) {
  return encodeStateAsUpdate(
    doc,
    encodeStateVector({ClientId(client): Clock(clock)}),
  );
}

Item _item(
  Doc doc,
  int client,
  AbstractContent content, {
  String parent = 'root',
  String? parentSub,
}) {
  return Item(
    id: Id(client: ClientId(client), clock: Clock(0)),
    parent: doc.itemParentForKey(parent),
    parentSub: parentSub,
    content: content,
  );
}

String _text(Doc doc) {
  return _rootContents(doc)
      .whereType<ContentString>()
      .map((c) => c.value)
      .join();
}

List<AbstractContent> _rootContents(Doc doc) {
  return [
    for (final item in doc.itemParentForKey('root').items())
      if (!item.deleted) item.content,
  ];
}

String? _mapText(Doc doc, String key) {
  final item = doc.itemParentForKey('attrs').currentFor(key);
  if (item == null || item.deleted || item.content is! ContentString) {
    return null;
  }
  return (item.content as ContentString).value;
}
