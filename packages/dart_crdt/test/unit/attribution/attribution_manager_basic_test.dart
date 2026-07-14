import 'package:dart_crdt/dart_crdt.dart';
import 'package:test/test.dart';

void main() {
  group('basic attribution managers', () {
    test('no-attribution manager handles visible and deleted content', () {
      final visible = noAttributionManager.readContent(
        client: ClientId(1),
        clock: Clock(0),
        deleted: false,
        content: ContentString('abc'),
      );
      final hiddenDeleted = noAttributionManager.readContent(
        client: ClientId(1),
        clock: Clock(0),
        deleted: true,
        content: ContentString('abc'),
        renderBehavior: AttributionRenderBehavior.never,
      );
      final renderedDeleted = noAttributionManager.readContent(
        client: ClientId(1),
        clock: Clock(0),
        deleted: true,
        content: ContentString('abc'),
        renderBehavior: AttributionRenderBehavior.always,
      );

      expect(visible.single.attributes, isNull);
      expect(visible.single.render, isTrue);
      expect(hiddenDeleted, isEmpty);
      expect(renderedDeleted.single.render, isTrue);
      expect(noAttributionManager.contentLength(_item('abc')), 3);
      expect(
        noAttributionManager.contentLength(_item('abc', deleted: true)),
        0,
      );
    });

    test('two-set manager slices inserted content and null ranges', () {
      final manager = TwoSetAttributionManager(
        inserts: IdMap()
          ..add(_id(1, 0), length: 2, attributes: [_attr('user', 'alice')])
          ..add(_id(1, 3), attributes: [_attr('user', 'bob')]),
      );

      final contents = manager.readContent(
        client: ClientId(1),
        clock: Clock(0),
        deleted: false,
        content: ContentString('abcd'),
      );

      expect(_strings(contents), ['ab', 'c', 'd']);
      expect(contents[0].attributes, [_attr('user', 'alice')]);
      expect(contents[1].attributes, isNull);
      expect(contents[2].attributes, [_attr('user', 'bob')]);
      expect(contents.every((content) => content.render), isTrue);
      expect(manager.contentLength(_item('abcd')), 4);
    });

    test('two-set manager renders attributed deleted slices only by default',
        () {
      final manager = TwoSetAttributionManager(
        deletes: IdMap()
          ..add(_id(1, 1), length: 2, attributes: [_attr('by', 'deleter')]),
      );
      final item = _item('abcd', deleted: true);

      final contents = manager.readContent(
        client: ClientId(1),
        clock: Clock(0),
        deleted: true,
        content: ContentString('abcd'),
        renderBehavior: AttributionRenderBehavior.never,
      );

      expect(_strings(contents), ['bc']);
      expect(contents.single.clock, Clock(1));
      expect(contents.single.attributes, [_attr('by', 'deleter')]);
      expect(contents.single.render, isFalse);
      expect(manager.contentLength(item), 2);
    });

    test('two-set manager can force deleted gap rendering', () {
      final manager = TwoSetAttributionManager(
        deletes: IdMap()..add(_id(1, 1), attributes: [_attr('by', 'deleter')]),
      );

      final contents = manager.readContent(
        client: ClientId(1),
        clock: Clock(0),
        deleted: true,
        content: ContentString('abc'),
        renderBehavior: AttributionRenderBehavior.always,
      );

      expect(_strings(contents), ['a', 'b', 'c']);
      expect(contents[0].attributes, isNull);
      expect(contents[1].attributes, [_attr('by', 'deleter')]);
      expect(contents[2].attributes, isNull);
      expect(contents.every((content) => content.render), isTrue);
    });

    test('uncountable format content has zero attributed length', () {
      final manager = TwoSetAttributionManager(
        inserts: IdMap()..add(_id(1, 0), attributes: [_attr('format', 'bold')]),
      );
      final item = Item(
        id: _id(1, 0),
        parent: ItemParent(key: 'root'),
        content: ContentFormat(key: 'bold', value: true),
      );

      final contents = manager.readContent(
        client: ClientId(1),
        clock: Clock(0),
        deleted: false,
        content: item.content,
      );

      expect(contents.single.attributes, [_attr('format', 'bold')]);
      expect(manager.contentLength(item), 0);
    });
  });
}

List<String> _strings(List<AttributedContent> contents) {
  return [
    for (final content in contents) (content.content as ContentString).value,
  ];
}

Item _item(String value, {bool deleted = false}) {
  final item = Item(
    id: _id(1, 0),
    parent: ItemParent(key: 'root'),
    content: ContentString(value),
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
