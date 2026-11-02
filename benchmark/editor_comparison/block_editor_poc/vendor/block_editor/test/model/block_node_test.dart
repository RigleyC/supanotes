import 'package:block_editor/block_editor.dart';
import 'package:test/test.dart';

void main() {
  group('BlockNode', () {
    test('auto-generates unique ids', () {
      final a = BlockNode(type: 'paragraph');
      final b = BlockNode(type: 'paragraph');
      expect(a.id, isNotEmpty);
      expect(a.id, isNot(equals(b.id)));
    });

    test('uses provided id', () {
      expect(BlockNode(id: 'custom-id', type: 'paragraph').id, 'custom-id');
    });

    test('attributes is immutable', () {
      final node = BlockNode(type: 'paragraph');
      expect(() => (node.attributes)['k'] = 'v', throwsUnsupportedError);
    });

    test('children is immutable', () {
      final node = BlockNode(type: 'bulletList');
      expect(
        () => (node.children).add(BlockNode(type: 'paragraph')),
        throwsUnsupportedError,
      );
    });

    test('delta is null by default', () {
      expect(BlockNode(type: 'divider').delta, isNull);
    });

    group('copyWith', () {
      test('preserves all fields when nothing overridden', () {
        final node = BlockNode(
          id: 'id1',
          type: 'paragraph',
          attributes: {'level': 1},
          delta: TextDelta.fromPlainText('hello'),
        );
        final copy = node.copyWith();
        expect(copy.id, node.id);
        expect(copy.type, node.type);
        expect(copy.attributes, node.attributes);
        expect(copy.delta, node.delta);
      });

      test('overrides type', () {
        expect(
          BlockNode(type: 'paragraph').copyWith(type: 'heading1').type,
          'heading1',
        );
      });

      test('overrides delta', () {
        final node = BlockNode(
          type: 'paragraph',
          delta: TextDelta.fromPlainText('old'),
        );
        final newDelta = TextDelta.fromPlainText('new');
        expect(node.copyWith(delta: newDelta).delta, equals(newDelta));
      });
    });

    group('toJson / fromJson round-trip', () {
      test('minimal node', () {
        final node = BlockNode(id: 'abc', type: 'divider');
        final restored = BlockNode.fromJson(node.toJson());
        expect(restored.id, node.id);
        expect(restored.type, node.type);
        expect(restored.delta, isNull);
      });

      test('node with attributes and delta', () {
        final node = BlockNode(
          id: 'xyz',
          type: 'heading1',
          attributes: {'level': 1, 'color': '#333'},
          delta: TextDelta([
            const TextOp('Title', attributes: InlineAttributes(bold: true)),
          ]),
        );
        expect(BlockNode.fromJson(node.toJson()), equals(node));
      });

      test('node with children', () {
        final child = BlockNode(
          id: 'child1',
          type: 'paragraph',
          delta: TextDelta.fromPlainText('child'),
        );
        final parent = BlockNode(
          id: 'parent1',
          type: 'bulletList',
          children: [child],
        );
        expect(BlockNode.fromJson(parent.toJson()).children.first.id, child.id);
      });

      test('empty fields are omitted from json', () {
        final json = BlockNode(id: 'id', type: 'paragraph').toJson();
        expect(json.containsKey('attributes'), isFalse);
        expect(json.containsKey('children'), isFalse);
        expect(json.containsKey('delta'), isFalse);
      });
    });

    group('equality', () {
      test('equal nodes', () {
        final a = BlockNode(
          id: 'same',
          type: 'paragraph',
          delta: TextDelta.fromPlainText('hello'),
        );
        final b = BlockNode(
          id: 'same',
          type: 'paragraph',
          delta: TextDelta.fromPlainText('hello'),
        );
        expect(a, equals(b));
      });

      test('different ids are not equal', () {
        expect(
          BlockNode(type: 'paragraph'),
          isNot(equals(BlockNode(type: 'paragraph'))),
        );
      });
    });
  });
}
