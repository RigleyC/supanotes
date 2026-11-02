import 'package:flutter_test/flutter_test.dart';
import 'package:block_editor/block_editor.dart';

BlockController makeController() =>
    BlockController(document: const BlockDocument([]));

BlockNode plainBlock(String text, {String type = BlockTypes.paragraph}) {
  return BlockNode(type: type, delta: TextDelta.fromPlainText(text));
}

BlockNode richBlock(List<DeltaOp> deltaOps) {
  return BlockNode(type: BlockTypes.paragraph, delta: TextDelta(deltaOps));
}

void main() {
  group('insertCharacter', () {
    test('inserts into empty block', () {
      final controller = makeController();
      final ops = EditorEditingOperations(controller);
      final node = plainBlock('');
      controller.append(node);
      controller.collapseSelection(node.id, 0);
      ops.insertCharacter('a');
      expect(controller.document.findById(node.id)!.delta!.plainText, 'a');
      controller.dispose();
    });

    test('inserts at start', () {
      final controller = makeController();
      final ops = EditorEditingOperations(controller);
      final node = plainBlock('bc');
      controller.append(node);
      controller.collapseSelection(node.id, 0);
      ops.insertCharacter('a');
      expect(controller.document.findById(node.id)!.delta!.plainText, 'abc');
      controller.dispose();
    });

    test('inserts at end', () {
      final controller = makeController();
      final ops = EditorEditingOperations(controller);
      final node = plainBlock('ab');
      controller.append(node);
      controller.collapseSelection(node.id, 2);
      ops.insertCharacter('c');
      expect(controller.document.findById(node.id)!.delta!.plainText, 'abc');
      controller.dispose();
    });

    test('inserts in middle', () {
      final controller = makeController();
      final ops = EditorEditingOperations(controller);
      final node = plainBlock('ac');
      controller.append(node);
      controller.collapseSelection(node.id, 1);
      ops.insertCharacter('b');
      expect(controller.document.findById(node.id)!.delta!.plainText, 'abc');
      controller.dispose();
    });

    test('inherits bold formatting from left neighbour', () {
      final controller = makeController();
      final ops = EditorEditingOperations(controller);
      final node = richBlock([
        const TextOp('hello', attributes: InlineAttributes(bold: true)),
      ]);
      controller.append(node);
      controller.collapseSelection(node.id, 5);
      ops.insertCharacter('!');
      final delta = controller.document.findById(node.id)!.delta!;
      expect(delta.plainText, 'hello!');
      expect(delta.ops.length, 1);
      expect((delta.ops.first as TextOp).attributes.bold, true);
      controller.dispose();
    });

    test('inherits no formatting when inserting at offset 0', () {
      final controller = makeController();
      final ops = EditorEditingOperations(controller);
      final node = richBlock([
        const TextOp('hello', attributes: InlineAttributes(bold: true)),
      ]);
      controller.append(node);
      controller.collapseSelection(node.id, 0);
      ops.insertCharacter('A');
      final delta = controller.document.findById(node.id)!.delta!;
      expect(delta.plainText, 'Ahello');
      expect((delta.ops.first as TextOp).attributes.bold, isNull);
      controller.dispose();
    });

    test(
      'preserves formatting of op to the right when inserting at boundary',
      () {
        final controller = makeController();
        final ops = EditorEditingOperations(controller);
        final node = richBlock([
          const TextOp('ab', attributes: InlineAttributes(bold: true)),
          const TextOp('cd', attributes: InlineAttributes(italic: true)),
        ]);
        controller.append(node);
        controller.collapseSelection(node.id, 2);
        ops.insertCharacter('X');
        final delta = controller.document.findById(node.id)!.delta!;
        expect(delta.plainText, 'abXcd');
        final boldOp = delta.ops[0] as TextOp;
        final italicOp = delta.ops[1] as TextOp;
        expect(boldOp.text, 'abX');
        expect(boldOp.attributes.bold, true);
        expect(italicOp.text, 'cd');
        expect(italicOp.attributes.italic, true);
        controller.dispose();
      },
    );

    test('does nothing when selection is not collapsed', () {
      final controller = makeController();
      final ops = EditorEditingOperations(controller);
      final node = plainBlock('abc');
      controller.append(node);
      controller.updateSelection(
        ExpandedSelection(
          anchor: SelectionPoint(blockId: node.id, offset: 0),
          focus: SelectionPoint(blockId: node.id, offset: 2),
        ),
      );
      ops.insertCharacter('X');
      expect(controller.document.findById(node.id)!.delta!.plainText, 'abc');
      controller.dispose();
    });

    test('advances cursor by character length', () {
      final controller = makeController();
      final ops = EditorEditingOperations(controller);
      final node = plainBlock('ab');
      controller.append(node);
      controller.collapseSelection(node.id, 1);
      ops.insertCharacter('X');
      final sel = controller.selection as CollapsedSelection;
      expect(sel.point.offset, 2);
      controller.dispose();
    });
  });

  group('backspace', () {
    test('deletes character before cursor', () {
      final controller = makeController();
      final ops = EditorEditingOperations(controller);
      final node = plainBlock('abc');
      controller.append(node);
      controller.collapseSelection(node.id, 2);
      ops.backspace();
      expect(controller.document.findById(node.id)!.delta!.plainText, 'ac');
      controller.dispose();
    });

    test('preserves formatting after deletion', () {
      final controller = makeController();
      final ops = EditorEditingOperations(controller);
      final node = richBlock([
        const TextOp('ab', attributes: InlineAttributes(bold: true)),
        const TextOp('cd', attributes: InlineAttributes(italic: true)),
      ]);
      controller.append(node);
      controller.collapseSelection(node.id, 2);
      ops.backspace();
      final delta = controller.document.findById(node.id)!.delta!;
      expect(delta.plainText, 'acd');
      expect((delta.ops[0] as TextOp).attributes.bold, true);
      expect((delta.ops[1] as TextOp).attributes.italic, true);
      controller.dispose();
    });

    test('merges with previous block preserving both deltas', () {
      final controller = makeController();
      final ops = EditorEditingOperations(controller);
      final prev = richBlock([
        const TextOp('hello', attributes: InlineAttributes(bold: true)),
      ]);
      final curr = richBlock([
        const TextOp('world', attributes: InlineAttributes(italic: true)),
      ]);
      controller.append(prev);
      controller.append(curr);
      controller.collapseSelection(curr.id, 0);
      ops.backspace();
      expect(controller.document.blocks.length, 1);
      final delta = controller.document.blocks.first.delta!;
      expect(delta.plainText, 'helloworld');
      expect((delta.ops[0] as TextOp).attributes.bold, true);
      expect((delta.ops[1] as TextOp).attributes.italic, true);
      controller.dispose();
    });

    test('does nothing at offset 0 of first block', () {
      final controller = makeController();
      final ops = EditorEditingOperations(controller);
      final node = plainBlock('abc');
      controller.append(node);
      controller.collapseSelection(node.id, 0);
      ops.backspace();
      expect(controller.document.blocks.length, 1);
      expect(controller.document.findById(node.id)!.delta!.plainText, 'abc');
      controller.dispose();
    });

    test('deletes expanded selection', () {
      final controller = makeController();
      final ops = EditorEditingOperations(controller);
      final node = plainBlock('abcde');
      controller.append(node);
      controller.updateSelection(
        ExpandedSelection(
          anchor: SelectionPoint(blockId: node.id, offset: 1),
          focus: SelectionPoint(blockId: node.id, offset: 4),
        ),
      );
      ops.backspace();
      expect(controller.document.findById(node.id)!.delta!.plainText, 'ae');
      controller.dispose();
    });
  });

  group('delete', () {
    test('deletes character at cursor', () {
      final controller = makeController();
      final ops = EditorEditingOperations(controller);
      final node = plainBlock('abc');
      controller.append(node);
      controller.collapseSelection(node.id, 1);
      ops.delete();
      expect(controller.document.findById(node.id)!.delta!.plainText, 'ac');
      controller.dispose();
    });

    test('preserves formatting after deletion', () {
      final controller = makeController();
      final ops = EditorEditingOperations(controller);
      final node = richBlock([
        const TextOp('ab', attributes: InlineAttributes(bold: true)),
        const TextOp('cd', attributes: InlineAttributes(italic: true)),
      ]);
      controller.append(node);
      controller.collapseSelection(node.id, 1);
      ops.delete();
      final delta = controller.document.findById(node.id)!.delta!;
      expect(delta.plainText, 'acd');
      expect((delta.ops[0] as TextOp).attributes.bold, true);
      expect((delta.ops[1] as TextOp).attributes.italic, true);
      controller.dispose();
    });

    test('merges with next block preserving both deltas', () {
      final controller = makeController();
      final ops = EditorEditingOperations(controller);
      final curr = richBlock([
        const TextOp('hello', attributes: InlineAttributes(bold: true)),
      ]);
      final next = richBlock([
        const TextOp('world', attributes: InlineAttributes(italic: true)),
      ]);
      controller.append(curr);
      controller.append(next);
      controller.collapseSelection(curr.id, 5);
      ops.delete();
      expect(controller.document.blocks.length, 1);
      final delta = controller.document.blocks.first.delta!;
      expect(delta.plainText, 'helloworld');
      expect((delta.ops[0] as TextOp).attributes.bold, true);
      expect((delta.ops[1] as TextOp).attributes.italic, true);
      controller.dispose();
    });

    test('does nothing at end of last block', () {
      final controller = makeController();
      final ops = EditorEditingOperations(controller);
      final node = plainBlock('abc');
      controller.append(node);
      controller.collapseSelection(node.id, 3);
      ops.delete();
      expect(controller.document.blocks.length, 1);
      controller.dispose();
    });
  });

  group('insertNewline', () {
    test('splits block at cursor preserving formatting on both halves', () {
      final controller = makeController();
      final ops = EditorEditingOperations(controller);
      final node = richBlock([
        const TextOp('hel', attributes: InlineAttributes(bold: true)),
        const TextOp('lo', attributes: InlineAttributes(italic: true)),
      ]);
      controller.append(node);
      controller.collapseSelection(node.id, 3);
      ops.insertNewline();
      expect(controller.document.blocks.length, 2);
      final first = controller.document.blocks[0].delta!;
      final second = controller.document.blocks[1].delta!;
      expect(first.plainText, 'hel');
      expect((first.ops.first as TextOp).attributes.bold, true);
      expect(second.plainText, 'lo');
      expect((second.ops.first as TextOp).attributes.italic, true);
      controller.dispose();
    });

    test('transforms empty list block to paragraph', () {
      final controller = makeController();
      final ops = EditorEditingOperations(controller);
      final node = BlockNode(
        type: BlockTypes.bulletList,
        delta: TextDelta.empty(),
      );
      controller.append(node);
      controller.collapseSelection(node.id, 0);
      ops.insertNewline();
      expect(controller.document.blocks.length, 1);
      expect(controller.document.blocks.first.type, BlockTypes.paragraph);
      controller.dispose();
    });

    test('new block cursor is at offset 0', () {
      final controller = makeController();
      final ops = EditorEditingOperations(controller);
      final node = plainBlock('hello');
      controller.append(node);
      controller.collapseSelection(node.id, 3);
      ops.insertNewline();
      final sel = controller.selection as CollapsedSelection;
      expect(sel.point.offset, 0);
      expect(sel.point.blockId, controller.document.blocks[1].id);
      controller.dispose();
    });
  });

  group('_deleteSelectedRange cross-block', () {
    test('merges blocks preserving formatting on both sides', () {
      final controller = makeController();
      final ops = EditorEditingOperations(controller);
      final first = richBlock([
        const TextOp('hello', attributes: InlineAttributes(bold: true)),
      ]);
      final second = richBlock([
        const TextOp('world', attributes: InlineAttributes(italic: true)),
      ]);
      controller.append(first);
      controller.append(second);
      controller.updateSelection(
        ExpandedSelection(
          anchor: SelectionPoint(blockId: first.id, offset: 3),
          focus: SelectionPoint(blockId: second.id, offset: 2),
        ),
      );
      ops.backspace();
      expect(controller.document.blocks.length, 1);
      final delta = controller.document.blocks.first.delta!;
      expect(delta.plainText, 'helrld');
      expect((delta.ops[0] as TextOp).attributes.bold, true);
      expect((delta.ops[1] as TextOp).attributes.italic, true);
      controller.dispose();
    });
  });

  group('indent / dedent', () {
    test('increments indent on list block', () {
      final controller = makeController();
      final ops = EditorEditingOperations(controller);
      final node = BlockNode(
        type: BlockTypes.bulletList,
        delta: TextDelta.fromPlainText('item'),
      );
      controller.append(node);
      controller.collapseSelection(node.id, 0);
      ops.indent();
      expect(controller.document.findById(node.id)!.attributes['indent'], 1);
      controller.dispose();
    });

    test('decrements indent on list block', () {
      final controller = makeController();
      final ops = EditorEditingOperations(controller);
      final node = BlockNode(
        type: BlockTypes.bulletList,
        attributes: const {'indent': 3},
        delta: TextDelta.fromPlainText('item'),
      );
      controller.append(node);
      controller.collapseSelection(node.id, 0);
      ops.dedent();
      expect(controller.document.findById(node.id)!.attributes['indent'], 2);
      controller.dispose();
    });

    test('does nothing on paragraph', () {
      final controller = makeController();
      final ops = EditorEditingOperations(controller);
      final node = plainBlock('text');
      controller.append(node);
      controller.collapseSelection(node.id, 0);
      ops.indent();
      expect(
        controller.document.findById(node.id)!.attributes['indent'],
        isNull,
      );
      controller.dispose();
    });

    test('clamps indent at 8', () {
      final controller = makeController();
      final ops = EditorEditingOperations(controller);
      final node = BlockNode(
        type: BlockTypes.bulletList,
        attributes: const {'indent': 8},
        delta: TextDelta.fromPlainText('item'),
      );
      controller.append(node);
      controller.collapseSelection(node.id, 0);
      ops.indent();
      expect(controller.document.findById(node.id)!.attributes['indent'], 8);
      controller.dispose();
    });

    test('clamps dedent at 0', () {
      final controller = makeController();
      final ops = EditorEditingOperations(controller);
      final node = BlockNode(
        type: BlockTypes.bulletList,
        attributes: const {'indent': 0},
        delta: TextDelta.fromPlainText('item'),
      );
      controller.append(node);
      controller.collapseSelection(node.id, 0);
      ops.dedent();
      expect(controller.document.findById(node.id)!.attributes['indent'], 0);
      controller.dispose();
    });
  });

  group('cursor movement', () {
    test('moveToLineStart sets offset to 0', () {
      final controller = makeController();
      final ops = EditorEditingOperations(controller);
      final node = plainBlock('hello');
      controller.append(node);
      controller.collapseSelection(node.id, 3);
      ops.moveToLineStart();
      final sel = controller.selection as CollapsedSelection;
      expect(sel.point.offset, 0);
      controller.dispose();
    });

    test('moveToLineEnd sets offset to text length', () {
      final controller = makeController();
      final ops = EditorEditingOperations(controller);
      final node = plainBlock('hello');
      controller.append(node);
      controller.collapseSelection(node.id, 0);
      ops.moveToLineEnd();
      final sel = controller.selection as CollapsedSelection;
      expect(sel.point.offset, 5);
      controller.dispose();
    });

    test('moveToDocumentStart moves to first block offset 0', () {
      final controller = makeController();
      final ops = EditorEditingOperations(controller);
      final a = plainBlock('aaa');
      final b = plainBlock('bbb');
      controller.append(a);
      controller.append(b);
      controller.collapseSelection(b.id, 3);
      ops.moveToDocumentStart();
      final sel = controller.selection as CollapsedSelection;
      expect(sel.point.blockId, a.id);
      expect(sel.point.offset, 0);
      controller.dispose();
    });

    test('moveToDocumentEnd moves to last block end', () {
      final controller = makeController();
      final ops = EditorEditingOperations(controller);
      final a = plainBlock('aaa');
      final b = plainBlock('bbb');
      controller.append(a);
      controller.append(b);
      controller.collapseSelection(a.id, 0);
      ops.moveToDocumentEnd();
      final sel = controller.selection as CollapsedSelection;
      expect(sel.point.blockId, b.id);
      expect(sel.point.offset, 3);
      controller.dispose();
    });

    test('moveWordLeft jumps to previous block end when at offset 0', () {
      final controller = makeController();
      final ops = EditorEditingOperations(controller);
      final a = plainBlock('hello');
      final b = plainBlock('world');
      controller.append(a);
      controller.append(b);
      controller.collapseSelection(b.id, 0);
      ops.moveWordLeft();
      final sel = controller.selection as CollapsedSelection;
      expect(sel.point.blockId, a.id);
      expect(sel.point.offset, 5);
      controller.dispose();
    });

    test('moveWordRight jumps to next block start when at end', () {
      final controller = makeController();
      final ops = EditorEditingOperations(controller);
      final a = plainBlock('hello');
      final b = plainBlock('world');
      controller.append(a);
      controller.append(b);
      controller.collapseSelection(a.id, 5);
      ops.moveWordRight();
      final sel = controller.selection as CollapsedSelection;
      expect(sel.point.blockId, b.id);
      expect(sel.point.offset, 0);
      controller.dispose();
    });
  });
}
