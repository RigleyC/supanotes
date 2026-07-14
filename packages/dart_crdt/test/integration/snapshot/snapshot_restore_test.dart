import 'package:dart_crdt/dart_crdt.dart';
import 'package:test/test.dart';

void main() {
  group('snapshot restore', () {
    test('restores empty snapshots and rejects GC-enabled origins', () {
      final restored = createDocFromSnapshot(Doc(gc: false), emptySnapshot);

      expect(restored.store.isEmpty, isTrue);
      expect(
        () => createDocFromSnapshot(Doc(), emptySnapshot),
        throwsA(isA<SnapshotRestoreException>()),
      );
    });

    test('splits partial structs and excludes dependent later changes', () {
      final origin = Doc(gc: false);
      origin.store.add(_textItem(origin, 1, 0, 'hello later'));
      final snap = createSnapshot(IdSet(), {ClientId(1): Clock(5)});

      final restored = createDocFromSnapshot(origin, snap);

      expect(_visibleText(restored), 'hello');
      expect(origin.store.structsFor(ClientId(1)), hasLength(2));
    });

    test('restores deleted items and map-style XML attributes', () {
      final deleted = Doc(gc: false);
      final item = _textItem(deleted, 2, 0, 'gone')..markDeleted();
      deleted.store.add(item);

      final attrs = Doc(gc: false);
      attrs.store.add(
        _textItem(attrs, 3, 0, 'hero', parent: 'section', parentSub: 'class'),
      );

      final restoredDeleted = createDocFromSnapshot(deleted, snapshot(deleted));
      final restoredAttrs = createDocFromSnapshot(attrs, snapshot(attrs));

      expect(_visibleText(restoredDeleted), isEmpty);
      final attr =
          restoredAttrs.itemParentForKey('section').currentFor('class');
      expect((attr!.content as ContentString).value, 'hero');
      expect(attr.deleted, isFalse);
    });

    test('restores nested type placeholders and ignores child changes after it',
        () {
      final origin = Doc(gc: false);
      origin.store
        ..add(
          Item(
            id: _id(4, 0),
            parent: origin.itemParentForKey('root'),
            content: ContentType(
              const SharedTypePlaceholder(
                kind: SharedTypeKind.xmlFragment,
                name: 'fragment',
              ),
            ),
          ),
        )
        ..add(_textItem(origin, 4, 1, 'late'));
      final snap = createSnapshot(IdSet(), {ClientId(4): Clock(1)});

      final restored = createDocFromSnapshot(origin, snap);
      final content = _rootContents(restored).single as ContentType;

      expect(content.sharedType.kind, SharedTypeKind.xmlFragment);
      expect(content.sharedType.name, 'fragment');
    });

    test('checks V1 and V2 update containment', () {
      final atSnapshot = _docWithText('hello');
      final later = _docWithText('hello!');
      final snap = snapshot(atSnapshot);
      final includedV1 = encodeStateAsUpdate(atSnapshot);
      final includedV2 = encodeStateAsUpdateV2(atSnapshot);
      final laterState = encodeStateVector({ClientId(1): Clock(5)});
      final laterV1 = encodeStateAsUpdate(later, laterState);
      final laterV2 = encodeStateAsUpdateV2(later, laterState);

      expect(snapshotContainsUpdate(snap, includedV1), isTrue);
      expect(snapshotContainsUpdateV2(snap, includedV2), isTrue);
      expect(snapshotContainsUpdate(snap, laterV1), isFalse);
      expect(snapshotContainsUpdateV2(snap, laterV2), isFalse);
    });
  });
}

Doc _docWithText(String text) {
  final doc = Doc(gc: false, clientId: ClientId(1));
  doc.store.add(_textItem(doc, 1, 0, text));
  return doc;
}

Item _textItem(
  Doc doc,
  int client,
  int clock,
  String text, {
  String parent = 'root',
  String? parentSub,
}) {
  return Item(
    id: _id(client, clock),
    origin: clock == 0 ? null : _id(client, clock - 1),
    parent: doc.itemParentForKey(parent),
    parentSub: parentSub,
    content: ContentString(text),
  );
}

String _visibleText(Doc doc) {
  return _rootContents(doc)
      .whereType<ContentString>()
      .map((content) => content.value)
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
