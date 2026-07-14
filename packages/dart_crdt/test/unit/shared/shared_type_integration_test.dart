import 'package:dart_crdt/src/content/content.dart';
import 'package:dart_crdt/src/doc/doc.dart';
import 'package:test/test.dart';

void main() {
  group('SharedType construction and roots', () {
    test('supports detached construction and pre-document observation', () {
      final type = SharedType(kind: SharedTypeKind.text, name: 'body');
      final events = <SharedTypeEvent>[];
      void observer(SharedTypeEvent event) => events.add(event);

      final subscription = type.observe(observer);

      type.markChanged('draft');
      expect(type.unobserve(observer), isTrue);
      type.markChanged('ignored');

      expect(subscription.isActive, isFalse);
      expect(type.doc, isNull);
      expect(type.parent, isNull);
      expect(type.isIntegrated, isFalse);
      expect(events, hasLength(1));
      expect(events.single.target, same(type));
      expect(events.single.keys, {'draft'});
      expect(events.single.transaction, isNull);
    });

    test('integrates root types and enforces one-document ownership', () {
      final doc = Doc();
      final otherDoc = Doc();
      final root = SharedType(kind: SharedTypeKind.array, name: 'items');

      expect(doc.integrateRoot(root, name: 'items'), same(root));
      expect(root.doc, same(doc));
      expect(root.isRoot, isTrue);
      expect(doc.get('items', SharedTypeKind.array), same(root));
      expect(doc.share, containsPair('items', root));
      expect(doc.toJson(), {
        'items': {'kind': 'array', 'name': 'items'},
      });
      expect(
        () => doc.get('items', SharedTypeKind.text),
        throwsA(isA<StateError>()),
      );
      expect(
        () => otherDoc.integrateRoot(root, name: 'items'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('SharedType parent integration', () {
    test('tracks nested parentage before and after document integration', () {
      final parent = SharedType(kind: SharedTypeKind.map, name: 'root');
      final child = SharedType(kind: SharedTypeKind.text, name: 'body');
      final grandchild = SharedType(kind: SharedTypeKind.array, name: 'runs');

      parent.integrateChild('body', child);
      child.integrateChild('runs', grandchild);

      expect(child.parent, same(parent));
      expect(child.parentKey, 'body');
      expect(grandchild.parent, same(child));
      expect(grandchild.doc, isNull);

      final doc = Doc()..integrateRoot(parent, name: 'root');

      expect(parent.doc, same(doc));
      expect(child.doc, same(doc));
      expect(grandchild.doc, same(doc));
      expect(parent.children['body'], same(child));
      expect(() => parent.children.clear(), throwsUnsupportedError);
      expect(
        () => SharedType(kind: SharedTypeKind.map).integrateChild('x', child),
        throwsA(isA<StateError>()),
      );
      expect(
        () => grandchild.integrateChild('cycle', parent),
        throwsA(isA<StateError>()),
      );
    });

    test('clones nested types without document or observer ownership', () {
      final parent = SharedType(kind: SharedTypeKind.map, name: 'root');
      final child = SharedType(kind: SharedTypeKind.text, name: 'body');
      var originalEvents = 0;

      parent
        ..integrateChild('body', child)
        ..observe((_) {
          originalEvents += 1;
        });

      final clone = parent.copy();
      final cloneChild = clone.children['body']!;

      clone.markChanged('ignored');
      parent.markChanged('title');

      expect(clone, parent);
      expect(identical(clone, parent), isFalse);
      expect(identical(cloneChild, child), isFalse);
      expect(clone.doc, isNull);
      expect(cloneChild.parent, same(clone));
      expect(originalEvents, 1);
    });
  });

  group('SharedType observation', () {
    test('dispatches direct and deep observers across transaction cleanup', () {
      final doc = Doc();
      final parent = doc.get('root');
      final child = parent.integrateChild(
        'child',
        SharedType(kind: SharedTypeKind.array, name: 'child'),
      );
      final calls = <String>[];
      void direct(SharedTypeEvent event) {
        calls.add('direct:${event.keys.single}:${event.transaction != null}');
      }

      void deep(SharedTypeEvent event) {
        calls.add('deep:${event.keys.single}:${event.transaction != null}');
      }

      child.observe(direct);
      parent.observeDeep(deep);

      child.markChanged('outside');
      doc.transact((_) => child.markChanged('inside'));
      expect(child.unobserve(direct), isTrue);
      expect(parent.unobserveDeep(deep), isTrue);
      child.markChanged('ignored');

      expect(calls, [
        'direct:outside:false',
        'deep:outside:false',
        'direct:inside:true',
        'deep:inside:true',
      ]);
    });
  });
}
