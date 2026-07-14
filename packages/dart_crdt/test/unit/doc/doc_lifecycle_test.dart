import 'package:dart_crdt/src/binary/any_value.dart';
import 'package:dart_crdt/src/binary/varint_codec.dart';
import 'package:dart_crdt/src/content/content.dart';
import 'package:dart_crdt/src/doc/doc.dart';
import 'package:dart_crdt/src/structs/id.dart';
import 'package:test/test.dart';

void main() {
  group('Doc lifecycle', () {
    test('creates default options and runtime state', () {
      final doc = Doc();

      expect(doc.gc, isTrue);
      expect(doc.gcFilter(Object()), isTrue);
      expect(doc.guid, isNotEmpty);
      expect(doc.collectionId, isNull);
      expect(doc.meta, const JsonNull());
      expect(doc.autoLoad, isFalse);
      expect(doc.shouldLoad, isFalse);
      expect(doc.isSuggestionDocument, isFalse);
      expect(doc.clientId.value, inInclusiveRange(0, maxSafeInteger));
      expect(doc.isLoaded, isFalse);
      expect(doc.isSynced, isFalse);
      expect(doc.isDestroyed, isFalse);
      expect(doc.subdocs, isEmpty);
      expect(doc.share, isEmpty);
    });

    test('applies custom options and validates client ids', () {
      final doc = Doc(
        gc: false,
        gcFilter: (_) => false,
        guid: 'doc-1',
        collectionId: 'team',
        meta: const JsonString('draft'),
        autoLoad: true,
        clientId: ClientId(42),
        isSuggestionDocument: true,
      );

      expect(doc.gc, isFalse);
      expect(doc.gcFilter(Object()), isFalse);
      expect(doc.guid, 'doc-1');
      expect(doc.collectionId, 'team');
      expect(doc.meta, const JsonString('draft'));
      expect(doc.autoLoad, isTrue);
      expect(doc.shouldLoad, isTrue);
      expect(doc.clientId, ClientId(42));
      expect(doc.isSuggestionDocument, isTrue);
      expect(
        () => Doc(clientId: ClientId(maxSafeInteger + 1)),
        throwsRangeError,
      );
    });

    test('loads idempotently and completes the load future once', () async {
      final doc = Doc();
      final whenLoaded = doc.whenLoaded;

      expect(doc.isLoaded, isFalse);
      expect(identical(doc.load(), whenLoaded), isTrue);
      await whenLoaded;

      expect(doc.isLoaded, isTrue);
      expect(doc.shouldLoad, isTrue);
      expect(identical(doc.load(), whenLoaded), isTrue);
    });

    test('tracks sync state changes and keeps the first sync future complete',
        () async {
      final doc = Doc();
      final whenSynced = doc.whenSynced;

      doc
        ..setSynced(true)
        ..setSynced(true);
      await whenSynced;

      expect(doc.isSynced, isTrue);

      doc.setSynced(false);

      expect(doc.isSynced, isFalse);
      expect(identical(doc.whenSynced, whenSynced), isTrue);
    });

    test('destroys idempotently and marks sync false', () async {
      final doc = Doc()..setSynced(true);
      final whenDestroyed = doc.whenDestroyed;

      expect(identical(doc.destroy(), whenDestroyed), isTrue);
      await whenDestroyed;
      expect(identical(doc.destroy(), whenDestroyed), isTrue);

      expect(doc.isDestroyed, isTrue);
      expect(doc.isSynced, isFalse);
    });
  });

  group('Doc root and subdocument state', () {
    test('registers roots, reuses lookups, and renders root JSON', () {
      final doc = Doc();
      final root = doc.root;
      final items = doc.get('items', SharedTypeKind.array);
      final body = doc.getText('body');
      final fragment = doc.getXmlFragment('xml');

      expect(root.kind, SharedTypeKind.map);
      expect(root.name, isEmpty);
      expect(identical(doc.get(), root), isTrue);
      expect(identical(doc.get('items', SharedTypeKind.array), items), isTrue);
      expect(identical(doc.getArray('items'), items), isTrue);
      expect(identical(doc.getMap(), root), isTrue);
      expect(body.kind, SharedTypeKind.text);
      expect(fragment.kind, SharedTypeKind.xmlFragment);
      expect(
        () => doc.get('items', SharedTypeKind.text),
        throwsA(isA<StateError>()),
      );
      expect(doc.share, containsPair('items', items));
      expect(
        () => doc.share['other'] = SharedType(
          kind: SharedTypeKind.map,
        ),
        throwsUnsupportedError,
      );
      expect(doc.toJson(), {
        '': {'kind': 'map', 'name': ''},
        'items': {'kind': 'array', 'name': 'items'},
        'body': {'kind': 'text', 'name': 'body'},
        'xml': {'kind': 'xmlFragment', 'name': 'xml'},
      });
    });

    test('tracks subdocuments with defensive snapshots', () {
      final doc = Doc();
      final first = Subdocument(guid: 'sub-1');
      final second = Subdocument(guid: 'sub-2', collectionId: 'team');

      expect(doc.addSubdocument(first), isTrue);
      expect(doc.addSubdocument(first), isFalse);
      expect(doc.addSubdocument(second), isTrue);
      expect(doc.getSubdocGuids(), {'sub-1', 'sub-2'});
      expect(doc.getSubdocs(), {first, second});
      expect(() => doc.subdocs.clear(), throwsUnsupportedError);

      expect(doc.removeSubdocument(first), isTrue);
      expect(doc.removeSubdocument(first), isFalse);
      expect(doc.getSubdocGuids(), {'sub-2'});
    });

    test('replaces client ids explicitly or with a generated safe id', () {
      final doc = Doc(clientId: ClientId(1));

      doc.replaceClientId(ClientId(2));
      expect(doc.clientId, ClientId(2));

      doc.replaceClientId();
      expect(doc.clientId.value, inInclusiveRange(0, maxSafeInteger));
    });
  });
}
