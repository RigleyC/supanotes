import 'package:block_editor/block_editor.dart';
import 'package:test/test.dart';

BlockNode paragraph({String? id, String text = ''}) =>
    BlockNode(id: id, type: 'paragraph', delta: TextDelta.fromPlainText(text));

void main() {
  late BlockController controller;

  setUp(() => controller = BlockController(document: BlockDocument.empty()));
  tearDown(() => controller.dispose());

  group('initial state', () {
    test('starts with one paragraph block', () {
      expect(controller.document.blocks.length, 1);
    });

    test('canUndo is false before any mutations', () {
      expect(controller.canUndo, isFalse);
    });

    test('canRedo is false initially', () {
      expect(controller.canRedo, isFalse);
    });
  });

  group('insertAt', () {
    test('inserts at index 0', () {
      controller.insertAt(0, paragraph(id: 'new'));
      expect(controller.document.blocks.first.id, 'new');
    });

    test('inserts at end', () {
      controller.insertAt(1, paragraph(id: 'last'));
      expect(controller.document.blocks.last.id, 'last');
    });

    test('throws RangeError for out-of-bounds index', () {
      expect(() => controller.insertAt(99, paragraph()), throwsRangeError);
    });

    test('emits insert change event', () async {
      final eventFuture = controller.changes.first;
      controller.insertAt(0, paragraph(id: 'ev'));
      final event = await eventFuture;
      expect(event.type, ChangeType.insert);
      expect(event.affectedIds, contains('ev'));
    });
  });

  group('append', () {
    test('adds block to end', () {
      controller.append(paragraph(id: 'appended'));
      expect(controller.document.blocks.last.id, 'appended');
    });
  });

  group('insertAfter', () {
    test('inserts after specified block', () {
      final firstId = controller.document.blocks.first.id;
      controller.insertAfter(firstId, paragraph(id: 'second'));
      expect(controller.document.blocks[1].id, 'second');
    });

    test('throws StateError for unknown id', () {
      expect(
        () => controller.insertAfter('bogus', paragraph()),
        throwsStateError,
      );
    });
  });

  group('delete', () {
    test('removes block by id', () {
      final id = controller.document.blocks.first.id;
      controller.delete(id);
      expect(controller.document.blocks, isEmpty);
    });

    test('does nothing for unknown id', () {
      final before = controller.document;
      controller.delete('nonexistent');
      expect(controller.document, equals(before));
    });

    test('emits delete change event', () async {
      final id = controller.document.blocks.first.id;
      final eventFuture = controller.changes.first;
      controller.delete(id);
      expect((await eventFuture).type, ChangeType.delete);
    });
  });

  group('update', () {
    test('replaces block in place', () {
      final id = controller.document.blocks.first.id;
      controller.update(
        id,
        BlockNode(
          id: id,
          type: 'heading1',
          delta: TextDelta.fromPlainText('Title'),
        ),
      );
      expect(controller.document.blocks.first.type, 'heading1');
    });

    test('does nothing for unknown id', () {
      final before = controller.document;
      controller.update('bogus', paragraph());
      expect(controller.document, equals(before));
    });
  });

  group('updateDelta', () {
    test('sets new delta on block', () {
      final id = controller.document.blocks.first.id;
      controller.updateDelta(id, TextDelta.fromPlainText('updated'));
      expect(controller.document.blocks.first.delta!.plainText, 'updated');
    });
  });

  group('updateAttributes', () {
    test('merges without wiping existing keys', () {
      final id = controller.document.blocks.first.id;
      controller.updateAttributes(id, {'a': 1});
      controller.updateAttributes(id, {'b': 2});
      final attrs = controller.document.blocks.first.attributes;
      expect(attrs['a'], 1);
      expect(attrs['b'], 2);
    });
  });

  group('transformType', () {
    test('changes block type', () {
      final id = controller.document.blocks.first.id;
      controller.transformType(id, 'heading2');
      expect(controller.document.blocks.first.type, 'heading2');
    });
  });

  group('applyInlineAttributes', () {
    test('applies bold to range', () {
      final id = controller.document.blocks.first.id;
      controller.updateDelta(id, TextDelta.fromPlainText('hello world'));
      controller.applyInlineAttributes(
        id,
        0,
        5,
        const InlineAttributes(bold: true),
      );
      final ops = controller.document.blocks.first.delta!.ops;
      expect((ops.first as TextOp).attributes.bold, isTrue);
      expect((ops.first as TextOp).text, 'hello');
    });
  });

  group('move', () {
    setUp(() {
      controller.append(paragraph(id: 'b2'));
      controller.append(paragraph(id: 'b3'));
    });

    test('moves block to new position', () {
      final firstId = controller.document.blocks.first.id;
      controller.move(firstId, 2);
      expect(controller.document.blocks.last.id, firstId);
    });

    test('throws StateError for non-root block', () {
      expect(() => controller.move('nonroot', 0), throwsStateError);
    });
  });

  group('undo / redo', () {
    test('undo reverts last mutation', () {
      final originalId = controller.document.blocks.first.id;
      controller.append(paragraph(id: 'added'));
      controller.undo();
      expect(controller.document.blocks.length, 1);
      expect(controller.document.blocks.first.id, originalId);
    });

    test('redo re-applies undone mutation', () {
      controller.append(paragraph(id: 'added'));
      controller.undo();
      controller.redo();
      expect(controller.document.blocks.length, 2);
    });

    test('new mutation clears redo stack', () {
      controller.append(paragraph());
      controller.undo();
      controller.append(paragraph());
      expect(controller.canRedo, isFalse);
    });

    test('undo does nothing when stack is empty', () {
      final before = controller.document;
      controller.undo();
      expect(controller.document, equals(before));
    });

    test('undo emits replace event', () async {
      controller.append(paragraph());
      final eventFuture = controller.changes.first;
      controller.undo();
      expect((await eventFuture).type, ChangeType.replace);
    });
  });

  group('replaceDocument', () {
    test('replaces entire document', () {
      controller.replaceDocument(
        BlockDocument([BlockNode(id: 'x', type: 'heading1')]),
      );
      expect(controller.document.blocks.first.type, 'heading1');
    });

    test('replacement is undoable', () {
      final original = controller.document;
      controller.replaceDocument(BlockDocument([BlockNode(type: 'heading1')]));
      controller.undo();
      expect(controller.document, equals(original));
    });
  });

  group('changes stream', () {
    test('document in event matches controller.document', () async {
      final eventFuture = controller.changes.first;
      controller.append(paragraph());
      final event = await eventFuture;
      expect(event.document, equals(controller.document));
    });

    test('selection changes do not appear on changes stream', () async {
      var documentChangeCount = 0;
      final sub = controller.changes.listen((_) => documentChangeCount++);
      controller.collapseSelection(controller.document.blocks.first.id, 0);
      await Future<void>.delayed(Duration.zero);
      expect(documentChangeCount, 0);
      await sub.cancel();
    });
  });

  group('selection', () {
    test('initial selection is NoSelection', () {
      expect(controller.selection, isA<NoSelection>());
    });

    test('updateSelection stores the given selection', () {
      final id = controller.document.blocks.first.id;
      final sel = CollapsedSelection(SelectionPoint(blockId: id, offset: 3));
      controller.updateSelection(sel);
      expect(controller.selection, equals(sel));
    });

    test('collapseSelection produces CollapsedSelection at correct offset', () {
      final id = controller.document.blocks.first.id;
      controller.collapseSelection(id, 5);
      final sel = controller.selection as CollapsedSelection;
      expect(sel.point.blockId, id);
      expect(sel.point.offset, 5);
    });

    test('clearSelection resets to NoSelection', () {
      final id = controller.document.blocks.first.id;
      controller.collapseSelection(id, 5);
      controller.clearSelection();
      expect(controller.selection, isA<NoSelection>());
    });

    test('updateSelection does not push undo snapshot', () {
      final id = controller.document.blocks.first.id;
      controller.collapseSelection(id, 5);
      expect(controller.canUndo, isFalse);
    });
  });

  group('selectionStream', () {
    test('emits when updateSelection is called', () async {
      final id = controller.document.blocks.first.id;
      final future = controller.selectionStream.first;
      controller.collapseSelection(id, 2);
      final emitted = await future;
      expect(emitted, isA<CollapsedSelection>());
    });

    test('emits NoSelection when clearSelection is called', () async {
      final id = controller.document.blocks.first.id;
      controller.collapseSelection(id, 2);
      final future = controller.selectionStream.first;
      controller.clearSelection();
      final emitted = await future;
      expect(emitted, isA<NoSelection>());
    });

    test('emits ExpandedSelection from selectAll', () async {
      controller.append(paragraph(id: 'b2', text: 'world'));
      final future = controller.selectionStream.first;
      controller.selectAll();
      final emitted = await future;
      expect(emitted, isA<ExpandedSelection>());
    });

    test('document mutations do not appear on selectionStream', () async {
      var selectionEventCount = 0;
      final sub = controller.selectionStream.listen(
        (_) => selectionEventCount++,
      );
      controller.append(paragraph());
      await Future<void>.delayed(Duration.zero);
      expect(selectionEventCount, 0);
      await sub.cancel();
    });
  });

  group('selectAll', () {
    test('anchor is at offset 0 of first block', () {
      controller.append(paragraph(id: 'b2', text: 'world'));
      controller.selectAll();
      final sel = controller.selection as ExpandedSelection;
      final firstId = controller.document.blocks.first.id;
      expect(sel.anchor.blockId, firstId);
      expect(sel.anchor.offset, 0);
    });

    test('focus is at end of last block delta', () {
      controller.append(paragraph(id: 'b2', text: 'world'));
      controller.selectAll();
      final sel = controller.selection as ExpandedSelection;
      expect(sel.focus.blockId, 'b2');
      expect(sel.focus.offset, 5);
    });

    test('does nothing when document has no blocks', () {
      final empty = BlockController(document: const BlockDocument([]));
      addTearDown(empty.dispose);
      empty.selectAll();
      expect(empty.selection, isA<NoSelection>());
    });

    test('focus offset is 0 when last block has no delta', () {
      final nodelta = BlockNode(id: 'nd', type: 'divider');
      controller.append(nodelta);
      controller.selectAll();
      final sel = controller.selection as ExpandedSelection;
      expect(sel.focus.blockId, 'nd');
      expect(sel.focus.offset, 0);
    });
  });

  group('selectedBlockIds', () {
    test('returns empty list for NoSelection', () {
      expect(controller.selectedBlockIds, isEmpty);
    });

    test('returns single id for CollapsedSelection', () {
      final id = controller.document.blocks.first.id;
      controller.collapseSelection(id, 0);
      expect(controller.selectedBlockIds, [id]);
    });

    test('returns all ids between start and end for ExpandedSelection', () {
      controller.append(paragraph(id: 'b2'));
      controller.append(paragraph(id: 'b3'));
      final firstId = controller.document.blocks.first.id;
      controller.updateSelection(
        ExpandedSelection(
          anchor: SelectionPoint(blockId: firstId, offset: 0),
          focus: const SelectionPoint(blockId: 'b3', offset: 0),
        ),
      );
      expect(controller.selectedBlockIds, [firstId, 'b2', 'b3']);
    });

    test('returns correct ids for backwards ExpandedSelection', () {
      controller.append(paragraph(id: 'b2'));
      controller.append(paragraph(id: 'b3'));
      final firstId = controller.document.blocks.first.id;
      controller.updateSelection(
        ExpandedSelection(
          anchor: const SelectionPoint(blockId: 'b3', offset: 0),
          focus: SelectionPoint(blockId: firstId, offset: 0),
        ),
      );
      expect(controller.selectedBlockIds, [firstId, 'b2', 'b3']);
    });

    test('returns empty list when block id not found in document', () {
      controller.updateSelection(
        const ExpandedSelection(
          anchor: SelectionPoint(blockId: 'ghost', offset: 0),
          focus: SelectionPoint(blockId: 'phantom', offset: 0),
        ),
      );
      expect(controller.selectedBlockIds, isEmpty);
    });
  });
}
