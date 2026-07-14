import 'package:dart_crdt/dart_crdt.dart';
import 'package:test/test.dart';

void main() {
  group('Awareness', () {
    test('sets local state and emits added and updated events', () {
      final awareness = Awareness(localClientId: ClientId(1));
      final changes = <AwarenessChange>[];
      awareness.changes.add(changes.add);

      final first = awareness.setLocalState({'name': 'Ada'});
      final second = awareness.setLocalField('cursor', 4);

      expect(first, isNotEmpty);
      expect(second, isNotEmpty);
      expect(awareness.localState!.toObject(), {
        'name': 'Ada',
        'cursor': 4,
      });
      expect(changes, hasLength(2));
      expect(changes[0].added, {ClientId(1)});
      expect(changes[1].updated, {ClientId(1)});
    });

    test('round-trips updates between clients', () {
      final left = Awareness(localClientId: ClientId(1));
      final right = Awareness(localClientId: ClientId(2));

      left.setLocalState({
        'user': {'name': 'Ada'},
        'cursor': 7,
      });
      final update = encodeAwarenessUpdate(left, clients: {ClientId(1)});
      final change = applyAwarenessUpdate(right, update);

      expect(change.added, {ClientId(1)});
      expect(right.states[ClientId(1)]!.toObject(), {
        'user': {'name': 'Ada'},
        'cursor': 7,
      });
    });

    test('ignores stale updates and accepts newer clocks', () {
      final source = Awareness(localClientId: ClientId(1));
      final target = Awareness(localClientId: ClientId(2));

      final oldUpdate = source.setLocalState({'cursor': 1});
      final newUpdate = source.setLocalState({'cursor': 2});

      target.applyAwarenessUpdate(newUpdate);
      final staleChange = target.applyAwarenessUpdate(oldUpdate);

      expect(staleChange.isEmpty, isTrue);
      expect(target.states[ClientId(1)]!.toObject(), {'cursor': 2});
    });

    test('removes visible states with encoded tombstones', () {
      final left = Awareness(localClientId: ClientId(1));
      final right = Awareness(localClientId: ClientId(2));

      applyAwarenessUpdate(right, left.setLocalState({'name': 'Ada'}));
      final removal = removeAwarenessStates(left, {ClientId(1)});
      final change = applyAwarenessUpdate(right, removal);

      expect(change.removed, {ClientId(1)});
      expect(right.states, isNot(contains(ClientId(1))));
      expect(left.localState, isNull);
    });

    test('rejects malformed payloads', () {
      final awareness = Awareness(localClientId: ClientId(1));

      expect(
        () => awareness.applyAwarenessUpdate([1, 1, 1, 2]),
        throwsFormatException,
      );
    });
  });
}
