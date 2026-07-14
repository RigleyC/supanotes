import 'package:dart_crdt/dart_crdt.dart';
import 'package:test/test.dart';

void main() {
  group('diff and snapshot attribution managers', () {
    test('attributes document insert diffs with supplied metadata', () {
      final previous = Doc(gc: false);
      final next = Doc(gc: false);
      applyUpdate(next, encodeStateAsUpdate(_sourceText(1, 'abc')));
      final manager = createAttributionManagerFromDiff(
        previous,
        next,
        attributions: Attributions(
          inserts: IdMap()
            ..add(_id(1, 0), length: 3, attributes: [_attr('user', 'alice')]),
        ),
      );

      final content = manager
          .readContent(
            client: ClientId(1),
            clock: Clock(0),
            deleted: false,
            content: ContentString('abc'),
          )
          .single;

      expect((content.content as ContentString).value, 'abc');
      expect(content.attributes, [_attr('user', 'alice')]);
      expect(manager.contentLength(_item(1, 'abc')), 3);
    });

    test('renders deleted diff content using delete attributions', () {
      final previous = _sourceText(1, 'gone');
      final next = _sourceText(1, 'gone', deleted: true);
      final manager = createAttributionManagerFromDiff(
        previous,
        next,
        attributions: Attributions(
          deletes: IdMap()
            ..add(_id(1, 0), length: 4, attributes: [_attr('by', 'bob')]),
        ),
      );
      final item = _item(1, 'gone', deleted: true);

      final content = manager
          .readContent(
            client: ClientId(1),
            clock: Clock(0),
            deleted: true,
            content: ContentString('gone'),
            renderBehavior: AttributionRenderBehavior.never,
          )
          .single;

      expect((content.content as ContentString).value, 'gone');
      expect(content.attributes, [_attr('by', 'bob')]);
      expect(manager.contentLength(item), 4);
    });

    test('emits change events and recomputes ranges after target changes', () {
      final previous = Doc(gc: false);
      final next = Doc(gc: false);
      final manager = createAttributionManagerFromDiff(previous, next);
      final events = <AttributionChangeEvent>[];
      manager.change.add(events.add);

      applyUpdate(
        next,
        encodeStateAsUpdate(_sourceText(2, 'xy')),
        origin: 'remote',
      );

      expect(events, hasLength(1));
      expect(events.single.changed.inserts.hasId(_id(2, 0)), isTrue);
      expect(events.single.origin, 'remote');
      final content = manager
          .readContent(
            client: ClientId(2),
            clock: Clock(0),
            deleted: false,
            content: ContentString('xy'),
          )
          .single;
      expect(content.attributes, isEmpty);
    });

    test('creates snapshot managers from state and delete-set differences', () {
      final deletes = IdSet()
        ..addRange(ClientId(1), IdRange(start: Clock(1), length: 1));
      final previous = createSnapshot(IdSet(), {ClientId(1): Clock(2)});
      final next = createSnapshot(deletes, {ClientId(1): Clock(5)});
      final manager = createAttributionManagerFromSnapshots(previous, next);

      final inserted = manager
          .readContent(
            client: ClientId(1),
            clock: Clock(2),
            deleted: false,
            content: ContentString('cde'),
          )
          .single;
      final deleted = manager
          .readContent(
            client: ClientId(1),
            clock: Clock(1),
            deleted: true,
            content: ContentString('b'),
            renderBehavior: AttributionRenderBehavior.never,
          )
          .single;

      expect((inserted.content as ContentString).value, 'cde');
      expect(inserted.attributes, isEmpty);
      expect((deleted.content as ContentString).value, 'b');
      expect(manager.contentLength(_item(1, 'b', clock: 1, deleted: true)), 1);
    });

    test('filters attributions by user/content attributes', () {
      final attrs = Attributions(
        inserts: IdMap()
          ..add(_id(1, 0), attributes: [_attr('user', 'alice')])
          ..add(_id(1, 1), attributes: [_attr('user', 'bob')]),
      );
      final filtered = attrs.filter(
        insertPredicate: (attributes) {
          return attributes.any((attribute) {
            return attribute.name == 'user' &&
                attribute.value.toObject() == 'alice';
          });
        },
      );

      expect(filtered.inserts.hasId(_id(1, 0)), isTrue);
      expect(filtered.inserts.hasId(_id(1, 1)), isFalse);
      expect(filtered.toContentMap().inserts.hasId(_id(1, 0)), isTrue);
    });
  });
}

Doc _sourceText(int client, String text, {bool deleted = false}) {
  final doc = Doc(gc: false, clientId: ClientId(client));
  final item = _item(client, text);
  if (deleted) {
    item.markDeleted();
  }
  doc.store.add(item);
  return doc;
}

Item _item(int client, String text, {int clock = 0, bool deleted = false}) {
  final item = Item(
    id: _id(client, clock),
    parent: ItemParent(key: 'root'),
    content: ContentString(text),
  );
  if (deleted) {
    item.markDeleted();
  }
  return item;
}

Id _id(int client, int clock) {
  return Id(client: ClientId(client), clock: Clock(clock));
}

ContentAttribute _attr(String name, Object? value) {
  return ContentAttribute(name, value);
}
