import 'package:block_editor/block_editor.dart';
import 'package:test/test.dart';

void main() {
  group('BlockDocument', () {
    test('empty factory creates one paragraph block', () {
      final doc = BlockDocument.empty();
      expect(doc.blocks.length, 1);
      expect(doc.blocks.first.type, 'paragraph');
    });

    test('isEmpty and isNotEmpty', () {
      expect(const BlockDocument([]).isEmpty, isTrue);
      expect(BlockDocument.empty().isNotEmpty, isTrue);
    });

    group('findById', () {
      test('finds root block', () {
        final node = BlockNode(id: 'root1', type: 'paragraph');
        expect(BlockDocument([node]).findById('root1'), equals(node));
      });

      test('finds nested block', () {
        final child = BlockNode(id: 'child1', type: 'paragraph');
        final parent = BlockNode(
          id: 'parent1',
          type: 'bulletList',
          children: [child],
        );
        expect(BlockDocument([parent]).findById('child1'), equals(child));
      });

      test('returns null when not found', () {
        expect(BlockDocument.empty().findById('nonexistent'), isNull);
      });
    });

    group('flatten', () {
      test('flat document stays flat', () {
        final doc = BlockDocument([
          BlockNode(type: 'paragraph'),
          BlockNode(type: 'paragraph'),
        ]);
        expect(doc.flatten().length, 2);
      });

      test('nested children included depth-first', () {
        final child = BlockNode(id: 'c', type: 'paragraph');
        final parent = BlockNode(
          id: 'p',
          type: 'bulletList',
          children: [child],
        );
        final flat = BlockDocument([parent]).flatten();
        expect(flat[0].id, 'p');
        expect(flat[1].id, 'c');
      });
    });

    group('toJson / fromJson round-trip', () {
      test('empty-blocks document', () {
        const original = BlockDocument([]);
        expect(BlockDocument.fromJson(original.toJson()).blocks, isEmpty);
      });

      test('document with multiple blocks', () {
        final original = BlockDocument([
          BlockNode(
            id: 'b1',
            type: 'heading1',
            delta: TextDelta.fromPlainText('Title'),
          ),
          BlockNode(
            id: 'b2',
            type: 'paragraph',
            delta: TextDelta.fromPlainText('Body'),
          ),
        ]);
        expect(BlockDocument.fromJson(original.toJson()), equals(original));
      });
    });

    group('copyWith', () {
      test('creates new document with replaced blocks', () {
        final original = BlockDocument.empty();
        final copy = original.copyWith(blocks: [BlockNode(type: 'heading1')]);
        expect(copy.blocks.first.type, 'heading1');
        expect(original.blocks.first.type, 'paragraph');
      });
    });
  });
}
