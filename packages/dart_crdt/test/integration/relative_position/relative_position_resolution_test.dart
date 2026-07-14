import 'package:dart_crdt/dart_crdt.dart';
import 'package:test/test.dart';

void main() {
  group('relative position resolution', () {
    test('creates and resolves root item positions with assoc', () {
      final doc = _syncedDoc([
        _item(1, 0, ContentString('abc')),
      ]);
      final type = doc.get('body', SharedTypeKind.text);

      final right = createRelativePositionFromTypeIndex(type, 1);
      final left = createRelativePositionFromTypeIndex(type, 1, assoc: -1);
      final end = createRelativePositionFromTypeIndex(type, 3);
      final start = createRelativePositionFromTypeIndex(type, 0, assoc: -1);

      expect(right.itemId, _id(1, 1));
      expect(right.rootName, 'body');
      expect(left.itemId, _id(1, 0));
      expect(_absoluteIndex(right, doc), 1);
      expect(_absoluteIndex(left, doc), 1);
      expect(end.toJson(), {'tname': 'body', 'assoc': 0});
      expect(_absoluteIndex(end, doc), 3);
      expect(_absoluteIndex(start, doc), 0);
    });

    test('resolves deleted item positions without counting deleted content',
        () {
      final doc = _syncedDoc(
        [_item(1, 0, ContentString('abc'))],
        deleteSet: IdSet()..add(_id(1, 1)),
      );
      final position = RelativePosition.item(_id(1, 1));

      final absolute =
          createAbsolutePositionFromRelativePosition(position, doc);
      final noFollow = createAbsolutePositionFromRelativePosition(
        position,
        doc,
        followRedoneItems: false,
      );

      expect(absolute?.index, 1);
      expect(noFollow?.index, 1);
    });

    test('resolves type-id positions from nested type content', () {
      final doc = _syncedDoc(
        [
          _item(
            1,
            0,
            ContentType(
              const SharedTypePlaceholder(
                kind: SharedTypeKind.text,
                name: 'child',
              ),
            ),
          ),
        ],
        kind: SharedTypeKind.array,
      );

      final absolute = createAbsolutePositionFromRelativePosition(
        RelativePosition.type(_id(1, 0), assoc: -1),
        doc,
      );

      expect(absolute?.type.kind, SharedTypeKind.text);
      expect(absolute?.type.name, 'child');
      expect(absolute?.index, 0);
      expect(
        createAbsolutePositionFromRelativePosition(
          RelativePosition.type(_id(9, 0)),
          doc,
        ),
        isNull,
      );
    });

    test('supports attribution-aware content length callbacks', () {
      final doc = _syncedDoc([
        _item(1, 0, ContentFormat(key: 'bold', value: true)),
        _item(1, 1, ContentString('ab'), origin: _id(1, 0)),
      ]);
      final type = doc.get('body', SharedTypeKind.text);

      final visible = createRelativePositionFromTypeIndex(type, 0);
      final countedFormat = createRelativePositionFromTypeIndex(
        type,
        0,
        contentLength: (_) => 1,
      );

      expect(visible.itemId, _id(1, 1));
      expect(countedFormat.itemId, _id(1, 0));
    });

    test('rejects unsupported or out-of-range resolution inputs', () {
      final doc = _syncedDoc([_item(1, 0, ContentString('a'))]);
      final type = doc.get('body', SharedTypeKind.text);

      expect(
        () => createRelativePositionFromTypeIndex(
          SharedType(kind: SharedTypeKind.text),
          0,
        ),
        throwsUnsupportedError,
      );
      expect(
        () => createRelativePositionFromTypeIndex(type, 2),
        throwsRangeError,
      );
      expect(
        createAbsolutePositionFromRelativePosition(
          RelativePosition.item(_id(9, 0)),
          doc,
        ),
        isNull,
      );
    });
  });
}

Doc _syncedDoc(
  List<Item> items, {
  IdSet? deleteSet,
  SharedTypeKind kind = SharedTypeKind.text,
}) {
  final source = Doc();
  for (final item in items) {
    source.store.add(item);
  }
  if (deleteSet != null) {
    source.store.addPendingDeleteSet(deleteSet);
  }
  final target = Doc()..get('body', kind);
  applyUpdate(target, encodeStateAsUpdate(source));
  return target;
}

Item _item(int client, int clock, AbstractContent content, {Id? origin}) {
  return Item(
    id: _id(client, clock),
    origin: origin,
    parent: origin == null ? ItemParent(key: 'body') : null,
    content: content,
  );
}

Id _id(int client, int clock) {
  return Id(client: ClientId(client), clock: Clock(clock));
}

int? _absoluteIndex(RelativePosition position, Doc doc) {
  return createAbsolutePositionFromRelativePosition(position, doc)?.index;
}
