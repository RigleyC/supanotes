import 'package:dart_crdt/dart_crdt.dart';
import 'package:test/test.dart';

void main() {
  group('suggestion changes', () {
    test('accepts and rejects all insertions', () {
      final previous = Doc(gc: false);
      final next = Doc(gc: false, clientId: ClientId(9));
      applyUpdate(next, encodeStateAsUpdate(_sourceText(1, 'abc')));
      final manager = createAttributionManagerFromDiff(previous, next);

      manager.acceptAllChanges();
      expect(_text(previous), 'abc');

      final rejectPrevious = Doc(gc: false);
      final rejectNext = Doc(gc: false, clientId: ClientId(10));
      applyUpdate(rejectNext, encodeStateAsUpdate(_sourceText(2, 'xyz')));
      final rejectManager = createAttributionManagerFromDiff(
        rejectPrevious,
        rejectNext,
      );

      rejectManager.rejectAllChanges();
      expect(_text(rejectNext), isEmpty);
    });

    test('accepts and rejects deletion suggestions', () {
      final acceptPrevious = _integrated(_sourceText(5, 'gone'));
      final acceptNext = _integrated(_sourceText(5, 'gone', deleted: true));
      final acceptManager = createAttributionManagerFromDiff(
        acceptPrevious,
        acceptNext,
      );

      acceptManager.acceptAllChanges();
      expect(_text(acceptPrevious), isEmpty);

      final rejectPrevious = _integrated(_sourceText(6, 'stay'));
      final rejectNext = _integrated(_sourceText(6, 'stay', deleted: true));
      final rejectManager = createAttributionManagerFromDiff(
        rejectPrevious,
        rejectNext,
      );

      rejectManager.rejectAllChanges();
      expect(_text(rejectNext), 'stay');
    });

    test('accepts and rejects selected ranges', () {
      final previous = Doc(gc: false);
      final next = Doc(gc: false, clientId: ClientId(9));
      applyUpdate(next, encodeStateAsUpdate(_sourceText(1, 'abc')));
      final manager = createAttributionManagerFromDiff(previous, next);

      manager.acceptChanges(_id(1, 0));
      manager.rejectChanges(_id(1, 1));

      expect(_text(previous), 'a');
      expect(_text(next), 'ac');
    });

    test('syncs target updates by origin when suggestion mode is disabled', () {
      final previous = Doc(gc: false);
      final next = Doc(gc: false);
      final manager = createAttributionManagerFromDiff(previous, next)
        ..suggestionMode = false
        ..suggestionOrigins = {'sync'};

      applyUpdate(
        next,
        encodeStateAsUpdate(_sourceText(1, 'x')),
        origin: 'sync',
      );
      applyUpdate(
        next,
        encodeStateAsUpdate(_sourceText(2, 'y')),
        origin: 'ignored',
      );

      expect(_text(previous), 'x');
      expect(_text(next), 'xy');
      expect(manager.suggestedChanges.inserts.hasId(_id(2, 0)), isTrue);
    });

    test('handles formatting, child-list content, and events', () {
      final previous = Doc(gc: false);
      final next = Doc(gc: false, clientId: ClientId(9));
      final manager = createAttributionManagerFromDiff(previous, next);
      final events = <AttributionChangeEvent>[];
      manager.change.add(events.add);

      applyUpdate(next, encodeStateAsUpdate(_sourceFormatAndChild()));

      expect(events, isNotEmpty);
      expect(_rootContents(next).whereType<ContentFormat>(), isNotEmpty);
      expect(_rootContents(next).whereType<ContentType>(), isNotEmpty);

      manager.acceptAllChanges();
      expect(_rootContents(previous).whereType<ContentType>(), isNotEmpty);

      final rejectPrevious = Doc(gc: false);
      final rejectNext = Doc(gc: false, clientId: ClientId(10));
      applyUpdate(rejectNext, encodeStateAsUpdate(_sourceFormatAndChild()));
      final rejectManager = createAttributionManagerFromDiff(
        rejectPrevious,
        rejectNext,
      );

      rejectManager.rejectAllChanges();
      expect(_rootContents(rejectNext), isEmpty);
    });

    test('rejects subdocument suggestions through undo integration', () {
      final previous = Doc(gc: false);
      final next = Doc(gc: false, clientId: ClientId(9));
      applyUpdate(next, encodeStateAsUpdate(_sourceSubdoc()));
      final manager = createAttributionManagerFromDiff(previous, next);

      expect(next.getSubdocGuids(), contains('suggested-child'));
      manager.rejectAllChanges();

      expect(next.getSubdocGuids(), isEmpty);
      expect(_rootContents(next), isEmpty);
    });
  });
}

Doc _sourceText(int client, String text, {bool deleted = false}) {
  final doc = Doc(gc: false, clientId: ClientId(client));
  final item = Item(
    id: _id(client, 0),
    parent: doc.itemParentForKey('root'),
    content: ContentString(text),
  );
  if (deleted) {
    item.markDeleted();
  }
  doc.store.add(item);
  return doc;
}

Doc _integrated(Doc source) {
  final doc = Doc(gc: false, clientId: ClientId(90));
  applyUpdate(doc, encodeStateAsUpdate(source));
  return doc;
}

Doc _sourceFormatAndChild() {
  final doc = Doc(gc: false, clientId: ClientId(3));
  doc.store
    ..add(
      Item(
        id: _id(3, 0),
        parent: doc.itemParentForKey('root'),
        content: ContentFormat(key: 'bold', value: true),
      ),
    )
    ..add(
      Item(
        id: _id(3, 1),
        origin: _id(3, 0),
        parent: doc.itemParentForKey('root'),
        content: ContentType(
          const SharedTypePlaceholder(
            kind: SharedTypeKind.xmlElement,
            name: 'node',
          ),
        ),
      ),
    );
  return doc;
}

Doc _sourceSubdoc() {
  final doc = Doc(gc: false, clientId: ClientId(4));
  doc.store.add(
    Item(
      id: _id(4, 0),
      parent: doc.itemParentForKey('root'),
      content: ContentDocument(guid: 'suggested-child'),
    ),
  );
  return doc;
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

Id _id(int client, int clock) {
  return Id(client: ClientId(client), clock: Clock(clock));
}
