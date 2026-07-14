import 'package:dart_crdt/dart_crdt.dart';
import 'package:test/test.dart';

/// M4: applying a remote update must fire `SharedTypeEvent`s on the receiving
/// replica's observers. Before M4, store-driven changes were recorded against
/// the parent (not the SharedType), so remote applies emitted nothing.
void main() {
  group('remote apply events', () {
    test('fires map observers with the changed keys on the receiver', () {
      final a = Doc();
      final b = Doc();
      final events = <Set<Object?>>[];
      b.getMap('m').observe((event) => events.add(event.keys));

      a.getMap('m')
        ..setAttr('title', 'Draft')
        ..setAttr('count', 1);
      applyUpdate(b, encodeStateAsUpdate(a));

      expect(events, isNotEmpty);
      expect(
        events.expand((k) => k).toSet(),
        containsAll(<Object?>['title', 'count']),
      );
      expect(b.getMap('m').getAttr('title'), 'Draft');
    });

    test('fires array observers on the receiver', () {
      final a = Doc();
      final b = Doc();
      var fired = 0;
      b.getArray('a').observe((event) => fired += 1);

      a.getArray('a').insertAll(0, [1, 2, 3]);
      applyUpdate(b, encodeStateAsUpdate(a));

      expect(fired, greaterThan(0));
      expect(b.getArray('a').toArray(), [1, 2, 3]);
    });

    test('does not double-fire for local mutations', () {
      final doc = Doc();
      final events = <Set<Object?>>[];
      doc.getMap('m').observe((event) => events.add(event.keys));

      doc.transact((_) => doc.getMap('m').setAttr('k', 'v'));

      // Exactly one event with the local key — not a second from the parent.
      expect(events, [
        {'k'},
      ]);
    });
  });
}
