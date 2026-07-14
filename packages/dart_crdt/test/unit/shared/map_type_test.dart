import 'package:dart_crdt/src/content/content.dart';
import 'package:dart_crdt/src/doc/doc.dart';
import 'package:dart_crdt/src/events/event_handler.dart';
import 'package:test/test.dart';

void main() {
  group('SharedType attribute map APIs', () {
    test('sets, gets, deletes, clears, and snapshots attributes', () {
      final type = SharedType(kind: SharedTypeKind.map)
        ..setAttr('title', 'Draft')
        ..setAttr('count', 1)
        ..setAttr('nullable', null);

      expect(type.attrSize, 3);
      expect(type.getAttr('title'), 'Draft');
      expect(type.getAttr('nullable'), isNull);
      expect(type.hasAttr('nullable'), isTrue);
      expect(type.getAttrs(), {
        'title': 'Draft',
        'count': 1,
        'nullable': null,
      });
      expect(type.attrKeys.toList(), ['title', 'count', 'nullable']);
      expect(type.attrValues.toList(), ['Draft', 1, null]);
      expect(
        type.attrEntries.map((entry) => '${entry.key}:${entry.value}').toList(),
        ['title:Draft', 'count:1', 'nullable:null'],
      );

      expect(type.deleteAttr('count'), isTrue);
      expect(type.deleteAttr('missing'), isFalse);
      expect(type.hasAttr('count'), isFalse);

      type.clearAttrs();

      expect(type.attrSize, 0);
      expect(type.getAttrs(), isEmpty);
      expect(() => type.setAttr('', 'bad'), throwsArgumentError);
    });

    test('uses last-writer-wins clocks for set and delete conflicts', () {
      final type = SharedType(kind: SharedTypeKind.map)
        ..setAttr('title', 'old', clock: 10)
        ..setAttr('title', 'ignored', clock: 9)
        ..setAttr('title', 'new', clock: 11);

      expect(type.getAttr('title'), 'new');
      expect(type.deleteAttr('title', clock: 10), isFalse);
      expect(type.hasAttr('title'), isTrue);
      expect(type.deleteAttr('title', clock: 12), isTrue);
      expect(type.hasAttr('title'), isFalse);

      type
        ..setAttr('title', 'stale', clock: 11)
        ..setAttr('title', 'restored', clock: 13);

      expect(type.getAttr('title'), 'restored');
    });

    test('tracks nested shared values and clone independence', () {
      final doc = Doc();
      final map = doc.get('attrs');
      final child = SharedType(kind: SharedTypeKind.text, name: 'body');

      map.setAttr('body', child);

      expect(child.parent, same(map));
      expect(child.parentKey, 'body');
      expect(child.doc, same(doc));
      expect(map.children['body'], same(child));
      expect(
        () => SharedType(kind: SharedTypeKind.map).setAttr('body', child),
        throwsA(isA<StateError>()),
      );

      final clone = map.copy();
      final cloneChild = clone.getAttr('body')! as SharedType;

      expect(clone.getAttrs().keys, ['body']);
      expect(cloneChild.parent, same(clone));
      expect(cloneChild.doc, isNull);

      expect(map.deleteAttr('body'), isTrue);
      expect(child.parent, isNull);
      expect(map.children, isNot(contains('body')));
      expect(clone.getAttr('body'), same(cloneChild));
    });

    test('iterates over stable snapshots while attributes mutate', () {
      final type = SharedType(kind: SharedTypeKind.map)
        ..setAttr('a', 1)
        ..setAttr('b', 2);
      final entries = type.attrEntries;
      final seen = <String>[];
      void record(String key, Object? value) {
        seen.add('$key:$value');
        if (key == 'a') {
          type.setAttr('c', 3);
        }
      }

      type.forEachAttr(record);

      expect(seen, ['a:1', 'b:2']);
      expect(entries.map((entry) => entry.key).toList(), ['a', 'b']);
      expect(type.attrKeys.toList(), ['a', 'b', 'c']);
    });

    test('emits event keys and preserves cleanup when observers throw', () {
      final doc = Doc();
      final type = doc.get('attrs');
      final calls = <String>[];

      type
        ..observe((event) {
          calls.add('first:${event.keys.join(',')}');
          throw StateError('observer failed');
        })
        ..observe((event) {
          calls.add('second:${event.target.getAttr('title')}');
        });

      expect(
        () => doc.transact((_) => type.setAttr('title', 'Draft')),
        throwsA(isA<EventDispatchException<SharedTypeEvent>>()),
      );

      expect(calls, ['first:title', 'second:Draft']);
      expect(type.getAttr('title'), 'Draft');
      expect(doc.currentTransaction, isNull);
      expect(doc.pendingTransactionCleanup, isEmpty);
    });
  });
}
