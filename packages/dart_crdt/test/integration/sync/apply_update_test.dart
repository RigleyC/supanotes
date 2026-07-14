import 'package:dart_crdt/src/content/content.dart';
import 'package:dart_crdt/src/doc/doc.dart';
import 'package:dart_crdt/src/metadata/id_set.dart';
import 'package:dart_crdt/src/structs/abstract_struct.dart';
import 'package:dart_crdt/src/structs/id.dart';
import 'package:dart_crdt/src/sync/apply_update.dart';
import 'package:dart_crdt/src/sync/state_update.dart';
import 'package:dart_crdt/src/sync/state_vector.dart';
import 'package:dart_crdt/src/sync/update_decoder.dart';
import 'package:test/test.dart' hide Skip;

void main() {
  group('applyUpdate', () {
    test('applies full V1 state and ignores duplicate updates', () {
      final source = _docWithItem('hi');
      final target = Doc(clientId: ClientId(8));
      final events = <DocUpdateEvent>[];
      target.update.add(events.add);
      final update = encodeStateAsUpdate(source);

      applyUpdate(target, update, origin: 'remote');
      applyUpdate(target, update, origin: 'duplicate');

      expect(target.store.getClock(ClientId(1)), Clock(2));
      expect(_rootText(target), 'hi');
      expect(events, hasLength(1));
      expect(events.single.origin, 'remote');
      expect(events.single.local, isFalse);
      expect(events.single.version, 1);
    });

    test('supports readUpdate with transaction origin and local=false', () {
      final source = _docWithItem('r');
      final target = Doc(clientId: ClientId(8));
      final locals = <bool>[];
      final origins = <Object?>[];
      final update = encodeStateAsUpdate(source);
      target.afterTransaction.add((transaction) {
        locals.add(transaction.local);
        origins.add(transaction.origin);
      });

      readUpdate(
        UpdateDecoderV1(update),
        target,
        origin: 'read-origin',
        update: update,
      );

      expect(_rootText(target), 'r');
      expect(locals, [isFalse]);
      expect(origins, ['read-origin']);
    });

    test('keeps causally incomplete structs pending and retries later', () {
      final target = Doc(clientId: ClientId(8));
      final first = encodeStateAsUpdate(_docWithItem('a'));
      final later = encodeStateAsUpdate(
        _docWithItem('abc'),
        encodeStateVector({ClientId(1): Clock(1)}),
      );

      applyUpdate(target, later);

      expect(target.store.isEmpty, isTrue);
      expect(target.store.pendingStructUpdate, isNotNull);
      expect(target.store.pendingStructs.isNotEmpty, isTrue);

      applyUpdate(target, first);

      expect(target.store.getClock(ClientId(1)), Clock(3));
      expect(target.store.pendingStructUpdate, isNull);
      expect(target.store.pendingStructs.isEmpty, isTrue);
      expect(_rootText(target), 'abc');
    });

    test('keeps delete sets pending and retries after structs arrive', () {
      final target = Doc(clientId: ClientId(8));
      final deleteOnly = Doc(clientId: ClientId(9))
        ..store.addPendingDeleteSet(IdSet()..add(_id(1, 0)));

      applyUpdate(target, encodeStateAsUpdate(deleteOnly));

      expect(target.store.pendingDeleteSet.hasId(_id(1, 0)), isTrue);

      applyUpdate(target, encodeStateAsUpdate(_docWithItem('x')));

      final item = target.store.structsFor(ClientId(1)).single as Item;
      expect(item.deleted, isTrue);
      expect(target.store.pendingDeleteSet.isEmpty, isTrue);
    });

    test('rejects malformed updates with trailing bytes', () {
      expect(
        () => applyUpdate(Doc(), const [0, 0, 99]),
        throwsA(isA<MalformedUpdateException>()),
      );
    });
  });

  group('applyUpdateV2', () {
    test('applies V2 state and emits V2 update events', () {
      final source = _docWithItem('v2');
      final target = Doc(clientId: ClientId(8));
      final events = <DocUpdateEvent>[];
      target.updateV2.add(events.add);

      applyUpdateV2(target, encodeStateAsUpdateV2(source), origin: 'v2');

      expect(target.store.getClock(ClientId(1)), Clock(2));
      expect(_rootText(target), 'v2');
      expect(events, hasLength(1));
      expect(events.single.origin, 'v2');
      expect(events.single.version, 2);
    });
  });
}

Doc _docWithItem(String text) {
  final doc = Doc(clientId: ClientId(1));
  doc.store.add(
    Item(
      id: _id(1, 0),
      parent: doc.itemParentForKey('root'),
      content: ContentString(text),
    ),
  );
  return doc;
}

String _rootText(Doc doc) {
  return doc
      .itemParentForKey('root')
      .items()
      .where((item) => !item.deleted)
      .map((item) => (item.content as ContentString).value)
      .join();
}

Id _id(int client, int clock) {
  return Id(client: ClientId(client), clock: Clock(clock));
}
