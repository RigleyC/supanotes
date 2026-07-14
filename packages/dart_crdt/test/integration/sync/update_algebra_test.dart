import 'package:dart_crdt/src/content/content.dart';
import 'package:dart_crdt/src/doc/doc.dart';
import 'package:dart_crdt/src/structs/abstract_struct.dart';
import 'package:dart_crdt/src/structs/id.dart';
import 'package:dart_crdt/src/sync/apply_update.dart';
import 'package:dart_crdt/src/sync/state_update.dart';
import 'package:dart_crdt/src/sync/state_vector.dart';
import 'package:dart_crdt/src/sync/update_algebra.dart';
import 'package:test/test.dart';

void main() {
  group('V1 update algebra', () {
    test('merges empty and duplicate update arrays', () {
      final update = encodeStateAsUpdate(_docWithItem(1, 'a'));
      final merged = mergeUpdates([update, update]);
      final target = Doc(clientId: ClientId(9));

      expect(mergeUpdates(const []), [0, 0]);
      applyUpdate(target, merged);

      expect(target.store.getClock(ClientId(1)), Clock(1));
      expect(_rootText(target), 'a');
    });

    test('is commutative for shuffled independent updates', () {
      final a = encodeStateAsUpdate(_docWithItem(1, 'a'));
      final b = encodeStateAsUpdate(_docWithItem(2, 'b'));
      final left = Doc(clientId: ClientId(9));
      final right = Doc(clientId: ClientId(10));

      applyUpdate(left, mergeUpdates([a, b, a]));
      applyUpdate(right, mergeUpdates([b, a, b]));

      expect(left.store.stateVector(), right.store.stateVector());
      expect(_rootText(left), _rootText(right));
    });

    test('diffs merged updates against a target state vector', () {
      final a = encodeStateAsUpdate(_docWithItem(1, 'a'));
      final b = encodeStateAsUpdate(_docWithItem(2, 'b'));
      final target = Doc(clientId: ClientId(9));
      applyUpdate(target, a);

      final diff =
          diffUpdate(mergeUpdates([a, b]), encodeDocumentStateVector(target));
      applyUpdate(target, diff);

      expect(target.store.stateVector(), {
        ClientId(1): Clock(1),
        ClientId(2): Clock(1),
      });
    });

    test('encodes state vectors directly from updates', () {
      final a = encodeStateAsUpdate(_docWithItem(1, 'a'));
      final b = encodeStateAsUpdate(_docWithItem(2, 'b'));

      expect(
        decodeStateVector(encodeStateVectorFromUpdate(mergeUpdates([a, b]))),
        {
          ClientId(1): Clock(1),
          ClientId(2): Clock(1),
        },
      );
    });

    test('advances the state vector across repeated structs for one client',
        () {
      // Two structs from the same client exercise the running-max in the
      // per-update state-vector derivation.
      final doc = Doc(clientId: ClientId(1));
      final parent = doc.itemParentForKey('root');
      doc.store
        ..add(
          Item(id: _id(1, 0), parent: parent, content: ContentString('a')),
        )
        // A different content type so the two structs do not merge into one.
        ..add(
          Item(
            id: _id(1, 1),
            origin: _id(1, 0),
            parent: parent,
            content: ContentAny.fromObjects(<Object?>['b']),
          ),
        );

      final vector = decodeStateVector(
        encodeStateVectorFromUpdate(encodeStateAsUpdate(doc)),
      );

      expect(vector, {ClientId(1): Clock(2)});
    });

    test('does not emit first-written skip output for unresolved updates', () {
      final unresolved = encodeStateAsUpdate(
        _docWithItem(1, 'abc'),
        encodeStateVector({ClientId(1): Clock(1)}),
      );

      expect(mergeUpdates([unresolved]), [0, 0]);
      expect(diffUpdate(unresolved, encodeStateVector(const {})), [0, 0]);
      expect(decodeStateVector(encodeStateVectorFromUpdate(unresolved)), {
        ClientId(1): Clock(3),
      });
    });
  });

  group('V2 update algebra', () {
    test('merges and diffs V2 updates', () {
      final a = encodeStateAsUpdateV2(_docWithItem(1, 'a'));
      final b = encodeStateAsUpdateV2(_docWithItem(2, 'b'));
      final merged = mergeUpdatesV2([b, a, b]);
      final target = Doc(clientId: ClientId(9));

      applyUpdateV2(target, diffUpdateV2(merged, encodeStateVector(const {})));

      expect(target.store.stateVector(), {
        ClientId(1): Clock(1),
        ClientId(2): Clock(1),
      });
      expect(decodeStateVector(encodeStateVectorFromUpdateV2(merged)), {
        ClientId(1): Clock(1),
        ClientId(2): Clock(1),
      });
    });
  });
}

Doc _docWithItem(int client, String text) {
  final doc = Doc(clientId: ClientId(client));
  doc.store.add(
    Item(
      id: _id(client, 0),
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
