import 'package:dart_crdt/dart_crdt.dart';
import 'package:test/test.dart';

/// M7: relative positions anchored to a NESTED (non-root) shared type now
/// resolve to the live store-backed type with a content-aware index — the
/// behaviour the changelog previously listed as unsupported (it used to return
/// a detached placeholder at index 0).
void main() {
  SharedType nestedText(Doc doc) {
    doc.getMap('root');
    return doc.getMap('root').getAttr('body')! as SharedType;
  }

  group('nested-type relative positions', () {
    test('end-of-type position resolves to the live nested type', () {
      final doc = Doc();
      doc.getMap('root').setAttr('body', SharedType(kind: SharedTypeKind.text));
      final body = nestedText(doc)..insertText(0, 'hello');

      final end = createRelativePositionFromTypeIndex(body, 5);
      // End-of-type anchors to the defining type id, not an item or root name.
      expect(end.typeId, isNotNull);
      expect(end.itemId, isNull);
      expect(end.rootName, isNull);

      final absolute = createAbsolutePositionFromRelativePosition(end, doc);
      expect(absolute, isNotNull);
      // The resolved type is the LIVE nested type, not a detached copy.
      expect(identical(absolute!.type, body), isTrue);
      expect(absolute.index, 5);
    });

    test('a mid-type position stays stable across inserts in the nested type',
        () {
      final doc = Doc();
      doc.getMap('root').setAttr('body', SharedType(kind: SharedTypeKind.text));
      final body = nestedText(doc)..insertText(0, 'world');

      final position = createRelativePositionFromTypeIndex(body, 3);
      expect(position.itemId, isNotNull);
      expect(
        createAbsolutePositionFromRelativePosition(position, doc)!.index,
        3,
      );

      body.insertText(0, 'XY');
      expect(
        createAbsolutePositionFromRelativePosition(position, doc)!.index,
        5,
      );
    });

    test('a nested-type position survives a binary round-trip to a peer', () {
      final a = Doc();
      a.getMap('root').setAttr('body', SharedType(kind: SharedTypeKind.text));
      (a.getMap('root').getAttr('body')! as SharedType).insertText(0, 'hello');
      final position = createRelativePositionFromTypeIndex(
        a.getMap('root').getAttr('body')! as SharedType,
        5,
      );

      final b = Doc();
      applyUpdate(b, encodeStateAsUpdate(a));

      final absolute = createAbsolutePositionFromRelativePosition(position, b);
      expect(absolute, isNotNull);
      final bBody = b.getMap('root').getAttr('body')! as SharedType;
      expect(identical(absolute!.type, bBody), isTrue);
      expect(absolute.index, 5);
    });

    test('a nested map position resolves to the live nested map', () {
      final doc = Doc();
      doc.getMap('root').setAttr('child', SharedType(kind: SharedTypeKind.map));
      final child = doc.getMap('root').getAttr('child')! as SharedType
        ..setAttr('a', 1)
        ..setAttr('b', 2);

      final end = createRelativePositionFromTypeIndex(child, 0);
      final absolute = createAbsolutePositionFromRelativePosition(end, doc);
      expect(identical(absolute!.type, child), isTrue);
    });
  });
}
