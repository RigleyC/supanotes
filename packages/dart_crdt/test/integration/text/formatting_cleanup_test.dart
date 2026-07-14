import 'package:dart_crdt/dart_crdt.dart';
import 'package:test/test.dart';

void main() {
  group('formatting cleanup', () {
    test('removes duplicate remote format markers', () {
      final doc = Doc(gc: false);

      applyUpdate(
        doc,
        encodeStateAsUpdate(
          _source(1, [
            ContentFormat(key: 'bold', value: true),
            ContentFormat(key: 'bold', value: true),
            ContentString('a'),
          ]),
        ),
      );

      expect(_visibleFormats(doc), ['bold:true']);
      expect(_deletedCount(doc), 1);
      expect(_plainText(doc), 'a');
    });

    test('keeps mid-text format removal markers', () {
      final doc = Doc(gc: false);

      applyUpdate(
        doc,
        encodeStateAsUpdate(
          _source(2, [
            ContentFormat(key: 'bold', value: true),
            ContentString('a'),
            ContentFormat(key: 'bold', value: null),
            ContentString('b'),
          ]),
        ),
      );

      expect(_visibleFormats(doc), ['bold:true', 'bold:null']);
      expect(_plainText(doc), 'ab');
      expect(_deletedCount(doc), 0);
    });

    test('removes contextless and trailing format changes', () {
      final doc = Doc(gc: false);

      applyUpdate(
        doc,
        encodeStateAsUpdate(
          _source(3, [
            ContentFormat(key: 'bold', value: true),
            ContentFormat(key: 'bold', value: null),
            ContentString('a'),
            ContentFormat(key: 'italic', value: true),
          ]),
        ),
      );

      expect(_visibleFormats(doc), isEmpty);
      expect(_plainText(doc), 'a');
      expect(_deletedCount(doc), 3);
    });

    test('does not emit direct text changes for identical attributes', () {
      final doc = Doc();
      final text = doc.get('body', SharedTypeKind.text)
        ..insertText(0, 'ab')
        ..format(0, 2, DeltaAttributes.fromJson({'bold': true}));
      final events = <SharedTypeEvent>[];
      text.observe(events.add);

      doc.transact((_) {
        text.format(0, 1, DeltaAttributes.fromJson({'bold': true}));
      });

      expect(events, isEmpty);
      expect(text.toDelta().toJson(), {
        'ops': [
          {
            'insert': 'ab',
            'attributes': {'bold': true},
          },
        ],
      });
    });
  });
}

Doc _source(int client, List<AbstractContent> contents) {
  final doc = Doc(gc: false, clientId: ClientId(client));
  final parent = doc.itemParentForKey('root');
  Id? origin;
  var clock = 0;
  for (final content in contents) {
    final item = Item(
      id: Id(client: ClientId(client), clock: Clock(clock)),
      origin: origin,
      parent: parent,
      content: content,
    );
    doc.store.add(item);
    origin = item.lastId;
    clock += item.length;
  }
  return doc;
}

List<String> _visibleFormats(Doc doc) {
  return [
    for (final item in doc.itemParentForKey('root').items())
      if (!item.deleted && item.content is ContentFormat)
        _format(
          (item.content as ContentFormat).key,
          (item.content as ContentFormat).value.toObject(),
        ),
  ];
}

String _plainText(Doc doc) {
  return doc
      .itemParentForKey('root')
      .items()
      .where((item) => !item.deleted)
      .map((item) => item.content)
      .whereType<ContentString>()
      .map((content) => content.value)
      .join();
}

int _deletedCount(Doc doc) {
  return doc.store.clients
      .expand((client) => doc.store.structsFor(client))
      .where((struct) => struct.deleted)
      .length;
}

String _format(String key, [Object? value]) => '$key:$value';
