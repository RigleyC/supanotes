import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:block_editor/block_editor.dart';

BlockController _makeController(List<BlockNode> blocks) {
  return BlockController(document: BlockDocument(blocks));
}

BlockNode _para(String id, String text) => BlockNode(
  id: id,
  type: BlockTypes.paragraph,
  delta: TextDelta([TextOp(text)]),
);

KeyEvent _keyDown(LogicalKeyboardKey key, {String? character}) => KeyDownEvent(
  logicalKey: key,
  physicalKey: PhysicalKeyboardKey.keyA,
  character: character,
  timeStamp: Duration.zero,
);

KeyEvent _keyUp(LogicalKeyboardKey key) => KeyUpEvent(
  logicalKey: key,
  physicalKey: PhysicalKeyboardKey.keyA,
  timeStamp: Duration.zero,
);

void main() {
  group('EditorEditingOperations — extendSelectionToLineStart', () {
    test('moves focus to offset 0 of its block', () {
      final ctrl = _makeController([_para('a', 'hello world')]);
      ctrl.collapseSelection('a', 5);
      final ops = EditorEditingOperations(ctrl);

      ops.extendSelectionToLineStart();

      final sel = ctrl.selection as ExpandedSelection;
      expect(sel.anchor.blockId, 'a');
      expect(sel.anchor.offset, 5);
      expect(sel.focus.blockId, 'a');
      expect(sel.focus.offset, 0);
    });

    test('does nothing when selection is NoSelection', () {
      final ctrl = _makeController([_para('a', 'hello')]);
      final ops = EditorEditingOperations(ctrl);

      ops.extendSelectionToLineStart();

      expect(ctrl.selection, isA<NoSelection>());
    });

    test('anchor stays when already an ExpandedSelection', () {
      final ctrl = _makeController([_para('a', 'hello world')]);
      ctrl.updateSelection(
        const ExpandedSelection(
          anchor: SelectionPoint(blockId: 'a', offset: 2),
          focus: SelectionPoint(blockId: 'a', offset: 8),
        ),
      );
      final ops = EditorEditingOperations(ctrl);

      ops.extendSelectionToLineStart();

      final sel = ctrl.selection as ExpandedSelection;
      expect(sel.anchor.offset, 2);
      expect(sel.focus.offset, 0);
    });
  });

  group('EditorEditingOperations — extendSelectionToLineEnd', () {
    test('moves focus to last offset of its block', () {
      final ctrl = _makeController([_para('a', 'hello world')]);
      ctrl.collapseSelection('a', 3);
      final ops = EditorEditingOperations(ctrl);

      ops.extendSelectionToLineEnd();

      final sel = ctrl.selection as ExpandedSelection;
      expect(sel.focus.blockId, 'a');
      expect(sel.focus.offset, 11);
    });

    test('handles empty block delta gracefully', () {
      final ctrl = _makeController([
        BlockNode(id: 'a', type: BlockTypes.paragraph),
      ]);
      ctrl.collapseSelection('a', 0);
      final ops = EditorEditingOperations(ctrl);

      ops.extendSelectionToLineEnd();

      final sel = ctrl.selection as ExpandedSelection;
      expect(sel.focus.offset, 0);
    });
  });

  group('EditorEditingOperations — extendSelectionToDocumentStart', () {
    test('moves focus to offset 0 of first block', () {
      final ctrl = _makeController([
        _para('a', 'first'),
        _para('b', 'second'),
        _para('c', 'third'),
      ]);
      ctrl.collapseSelection('c', 3);
      final ops = EditorEditingOperations(ctrl);

      ops.extendSelectionToDocumentStart();

      final sel = ctrl.selection as ExpandedSelection;
      expect(sel.anchor.blockId, 'c');
      expect(sel.focus.blockId, 'a');
      expect(sel.focus.offset, 0);
    });

    test('does nothing when document has no blocks', () {
      final ctrl = _makeController([]);
      final ops = EditorEditingOperations(ctrl);

      ops.extendSelectionToDocumentStart();

      expect(ctrl.selection, isA<NoSelection>());
    });
  });

  group('EditorEditingOperations — extendSelectionToDocumentEnd', () {
    test('moves focus to last offset of last block', () {
      final ctrl = _makeController([
        _para('a', 'first'),
        _para('b', 'second'),
        _para('c', 'third'),
      ]);
      ctrl.collapseSelection('a', 0);
      final ops = EditorEditingOperations(ctrl);

      ops.extendSelectionToDocumentEnd();

      final sel = ctrl.selection as ExpandedSelection;
      expect(sel.anchor.blockId, 'a');
      expect(sel.focus.blockId, 'c');
      expect(sel.focus.offset, 5);
    });
  });

  group('EditorEditingOperations — extendSelectionWordLeft', () {
    test('moves focus one word boundary left within block', () {
      final ctrl = _makeController([_para('a', 'hello world')]);
      ctrl.collapseSelection('a', 11);
      final ops = EditorEditingOperations(ctrl);

      ops.extendSelectionWordLeft();

      final sel = ctrl.selection as ExpandedSelection;
      expect(sel.focus.blockId, 'a');
      expect(sel.focus.offset, 6);
    });

    test('crosses into previous block when focus is at offset 0', () {
      final ctrl = _makeController([_para('a', 'first'), _para('b', 'second')]);
      ctrl.collapseSelection('b', 0);
      final ops = EditorEditingOperations(ctrl);

      ops.extendSelectionWordLeft();

      final sel = ctrl.selection as ExpandedSelection;
      expect(sel.focus.blockId, 'a');
      expect(sel.focus.offset, 5);
    });

    test(
      'does nothing at start of first block — selection stays collapsed',
      () {
        final ctrl = _makeController([_para('a', 'hello')]);
        ctrl.collapseSelection('a', 0);
        final ops = EditorEditingOperations(ctrl);

        ops.extendSelectionWordLeft();

        expect(ctrl.selection, isA<CollapsedSelection>());
        final sel = ctrl.selection as CollapsedSelection;
        expect(sel.point.blockId, 'a');
        expect(sel.point.offset, 0);
      },
    );
  });

  group('EditorEditingOperations — extendSelectionWordRight', () {
    test('moves focus one word boundary right within block', () {
      final ctrl = _makeController([_para('a', 'hello world')]);
      ctrl.collapseSelection('a', 0);
      final ops = EditorEditingOperations(ctrl);

      ops.extendSelectionWordRight();

      final sel = ctrl.selection as ExpandedSelection;
      expect(sel.focus.blockId, 'a');
      expect(sel.focus.offset, 5);
    });

    test('crosses into next block when focus is at end', () {
      final ctrl = _makeController([_para('a', 'first'), _para('b', 'second')]);
      ctrl.collapseSelection('a', 5);
      final ops = EditorEditingOperations(ctrl);

      ops.extendSelectionWordRight();

      final sel = ctrl.selection as ExpandedSelection;
      expect(sel.focus.blockId, 'b');
      expect(sel.focus.offset, 0);
    });

    test('does nothing at end of last block — selection stays collapsed', () {
      final ctrl = _makeController([_para('a', 'hello')]);
      ctrl.collapseSelection('a', 5);
      final ops = EditorEditingOperations(ctrl);

      ops.extendSelectionWordRight();

      expect(ctrl.selection, isA<CollapsedSelection>());
      final sel = ctrl.selection as CollapsedSelection;
      expect(sel.point.blockId, 'a');
      expect(sel.point.offset, 5);
    });
  });

  group('KeyboardShortcutHandler — ignored event types', () {
    test('returns ignored for KeyUpEvent', () {
      final ctrl = _makeController([_para('a', 'hello')]);
      ctrl.collapseSelection('a', 0);
      final ops = EditorEditingOperations(ctrl);
      final handler = KeyboardShortcutHandler(controller: ctrl, ops: ops);

      expect(
        handler.handle(_keyUp(LogicalKeyboardKey.keyA), const ModifierKeys()),
        KeyEventResult.ignored,
      );
    });
  });

  group('KeyboardShortcutHandler — escape', () {
    test('clears selection', () {
      final ctrl = _makeController([_para('a', 'hello')]);
      ctrl.updateSelection(
        const ExpandedSelection(
          anchor: SelectionPoint(blockId: 'a', offset: 0),
          focus: SelectionPoint(blockId: 'a', offset: 5),
        ),
      );
      final ops = EditorEditingOperations(ctrl);
      final handler = KeyboardShortcutHandler(controller: ctrl, ops: ops);

      final result = handler.handle(
        _keyDown(LogicalKeyboardKey.escape),
        const ModifierKeys(),
      );

      expect(result, KeyEventResult.handled);
      expect(ctrl.selection, isA<NoSelection>());
    });
  });

  group('KeyboardShortcutHandler — character insertion', () {
    test('inserts printable character', () {
      final ctrl = _makeController([_para('a', '')]);
      ctrl.collapseSelection('a', 0);
      final ops = EditorEditingOperations(ctrl);
      final handler = KeyboardShortcutHandler(controller: ctrl, ops: ops);

      final result = handler.handle(
        _keyDown(LogicalKeyboardKey.keyH, character: 'h'),
        const ModifierKeys(),
      );

      expect(result, KeyEventResult.handled);
      expect(ctrl.document.findById('a')!.delta!.plainText, 'h');
    });

    test('ignores control characters', () {
      final ctrl = _makeController([_para('a', 'hello')]);
      ctrl.collapseSelection('a', 5);
      final ops = EditorEditingOperations(ctrl);
      final handler = KeyboardShortcutHandler(controller: ctrl, ops: ops);

      final result = handler.handle(
        _keyDown(LogicalKeyboardKey.keyA, character: '\x01'),
        const ModifierKeys(),
      );

      expect(result, KeyEventResult.ignored);
    });
  });

  group('KeyboardShortcutHandler — unknown key', () {
    test('returns ignored for unmapped key with no character', () {
      final ctrl = _makeController([_para('a', 'hello')]);
      ctrl.collapseSelection('a', 0);
      final ops = EditorEditingOperations(ctrl);
      final handler = KeyboardShortcutHandler(controller: ctrl, ops: ops);

      final result = handler.handle(
        _keyDown(LogicalKeyboardKey.f5),
        const ModifierKeys(),
      );

      expect(result, KeyEventResult.ignored);
    });
  });

  group('KeyboardShortcutHandler — cmd shortcuts', () {
    test('undo dispatched on Cmd+Z', () {
      final ctrl = _makeController([_para('a', 'hello')]);
      ctrl.collapseSelection('a', 5);
      final ops = EditorEditingOperations(ctrl);
      final handler = KeyboardShortcutHandler(controller: ctrl, ops: ops);

      ops.insertCharacter('!');
      expect(ctrl.document.findById('a')!.delta!.plainText, 'hello!');

      handler.handle(
        _keyDown(LogicalKeyboardKey.keyZ),
        const ModifierKeys(cmd: true),
      );

      expect(ctrl.document.findById('a')!.delta!.plainText, 'hello');
    });

    test('select all dispatched on Cmd+A', () {
      final ctrl = _makeController([_para('a', 'first'), _para('b', 'second')]);
      ctrl.collapseSelection('a', 0);
      final ops = EditorEditingOperations(ctrl);
      final handler = KeyboardShortcutHandler(controller: ctrl, ops: ops);

      handler.handle(
        _keyDown(LogicalKeyboardKey.keyA),
        const ModifierKeys(cmd: true),
      );

      expect(ctrl.selection, isA<ExpandedSelection>());
    });

    test('bold dispatched on Cmd+B with expanded selection', () {
      final ctrl = _makeController([_para('a', 'hello')]);
      ctrl.updateSelection(
        const ExpandedSelection(
          anchor: SelectionPoint(blockId: 'a', offset: 0),
          focus: SelectionPoint(blockId: 'a', offset: 5),
        ),
      );
      final ops = EditorEditingOperations(ctrl);
      final handler = KeyboardShortcutHandler(controller: ctrl, ops: ops);

      handler.handle(
        _keyDown(LogicalKeyboardKey.keyB),
        const ModifierKeys(cmd: true),
      );

      final node = ctrl.document.findById('a')!;
      final op = node.delta!.ops.first as TextOp;
      expect(op.attributes.bold, true);
    });
  });

  group('KeyboardShortcutHandler — Home/End variants', () {
    test('plain Home moves to line start', () {
      final ctrl = _makeController([_para('a', 'hello world')]);
      ctrl.collapseSelection('a', 7);
      final ops = EditorEditingOperations(ctrl);
      final handler = KeyboardShortcutHandler(controller: ctrl, ops: ops);

      handler.handle(_keyDown(LogicalKeyboardKey.home), const ModifierKeys());

      final sel = ctrl.selection as CollapsedSelection;
      expect(sel.point.offset, 0);
    });

    test('Shift+Home extends selection to line start', () {
      final ctrl = _makeController([_para('a', 'hello world')]);
      ctrl.collapseSelection('a', 7);
      final ops = EditorEditingOperations(ctrl);
      final handler = KeyboardShortcutHandler(controller: ctrl, ops: ops);

      handler.handle(
        _keyDown(LogicalKeyboardKey.home),
        const ModifierKeys(shift: true),
      );

      final sel = ctrl.selection as ExpandedSelection;
      expect(sel.anchor.offset, 7);
      expect(sel.focus.offset, 0);
    });

    test('plain End moves to line end', () {
      final ctrl = _makeController([_para('a', 'hello world')]);
      ctrl.collapseSelection('a', 3);
      final ops = EditorEditingOperations(ctrl);
      final handler = KeyboardShortcutHandler(controller: ctrl, ops: ops);

      handler.handle(_keyDown(LogicalKeyboardKey.end), const ModifierKeys());

      final sel = ctrl.selection as CollapsedSelection;
      expect(sel.point.offset, 11);
    });

    test('Shift+End extends selection to line end', () {
      final ctrl = _makeController([_para('a', 'hello world')]);
      ctrl.collapseSelection('a', 3);
      final ops = EditorEditingOperations(ctrl);
      final handler = KeyboardShortcutHandler(controller: ctrl, ops: ops);

      handler.handle(
        _keyDown(LogicalKeyboardKey.end),
        const ModifierKeys(shift: true),
      );

      final sel = ctrl.selection as ExpandedSelection;
      expect(sel.anchor.offset, 3);
      expect(sel.focus.offset, 11);
    });
  });
  group(
    'KeyboardShortcutHandler — Shift+Arrow cross-block selection routing',
    () {
      test('Shift+ArrowRight extends selection right', () {
        final ctrl = _makeController([
          _para('a', 'hello'),
          _para('b', 'world'),
        ]);
        ctrl.collapseSelection('a', 5);
        final ops = EditorEditingOperations(ctrl);
        final handler = KeyboardShortcutHandler(controller: ctrl, ops: ops);

        handler.handle(
          _keyDown(LogicalKeyboardKey.arrowRight),
          const ModifierKeys(shift: true),
        );

        final sel = ctrl.selection as ExpandedSelection;
        expect(sel.anchor.blockId, 'a');
        expect(sel.anchor.offset, 5);
        expect(sel.focus.blockId, 'b');
        expect(sel.focus.offset, 0);
      });

      test('Shift+ArrowLeft extends selection left', () {
        final ctrl = _makeController([
          _para('a', 'hello'),
          _para('b', 'world'),
        ]);
        ctrl.collapseSelection('b', 0);
        final ops = EditorEditingOperations(ctrl);
        final handler = KeyboardShortcutHandler(controller: ctrl, ops: ops);

        handler.handle(
          _keyDown(LogicalKeyboardKey.arrowLeft),
          const ModifierKeys(shift: true),
        );

        final sel = ctrl.selection as ExpandedSelection;
        expect(sel.anchor.blockId, 'b');
        expect(sel.anchor.offset, 0);
        expect(sel.focus.blockId, 'a');
        expect(sel.focus.offset, 5);
      });

      test('Shift+ArrowDown extends selection to end of next block', () {
        final ctrl = _makeController([
          _para('a', 'hello'),
          _para('b', 'world'),
        ]);
        ctrl.collapseSelection('a', 2);
        final ops = EditorEditingOperations(ctrl);
        final handler = KeyboardShortcutHandler(controller: ctrl, ops: ops);

        handler.handle(
          _keyDown(LogicalKeyboardKey.arrowDown),
          const ModifierKeys(shift: true),
        );

        final sel = ctrl.selection as ExpandedSelection;
        expect(sel.anchor.blockId, 'a');
        expect(sel.focus.blockId, 'b');
        expect(sel.focus.offset, 5);
      });

      test('Shift+ArrowUp extends selection to end of previous block', () {
        final ctrl = _makeController([
          _para('a', 'hello'),
          _para('b', 'world'),
        ]);
        ctrl.collapseSelection('b', 3);
        final ops = EditorEditingOperations(ctrl);
        final handler = KeyboardShortcutHandler(controller: ctrl, ops: ops);

        handler.handle(
          _keyDown(LogicalKeyboardKey.arrowUp),
          const ModifierKeys(shift: true),
        );

        final sel = ctrl.selection as ExpandedSelection;
        expect(sel.anchor.blockId, 'b');
        expect(sel.focus.blockId, 'a');
        expect(sel.focus.offset, 5);
      });

      test(
        'Shift+Alt+ArrowRight extends selection by word across block boundary',
        () {
          final ctrl = _makeController([
            _para('a', 'hello'),
            _para('b', 'world'),
          ]);
          ctrl.collapseSelection('a', 5);
          final ops = EditorEditingOperations(ctrl);
          final handler = KeyboardShortcutHandler(controller: ctrl, ops: ops);

          handler.handle(
            _keyDown(LogicalKeyboardKey.arrowRight),
            const ModifierKeys(shift: true, alt: true),
          );

          final sel = ctrl.selection as ExpandedSelection;
          expect(sel.anchor.blockId, 'a');
          expect(sel.focus.blockId, 'b');
          expect(sel.focus.offset, 0);
        },
      );

      test(
        'Shift+Alt+ArrowLeft extends selection by word across block boundary',
        () {
          final ctrl = _makeController([
            _para('a', 'hello'),
            _para('b', 'world'),
          ]);
          ctrl.collapseSelection('b', 0);
          final ops = EditorEditingOperations(ctrl);
          final handler = KeyboardShortcutHandler(controller: ctrl, ops: ops);

          handler.handle(
            _keyDown(LogicalKeyboardKey.arrowLeft),
            const ModifierKeys(shift: true, alt: true),
          );

          final sel = ctrl.selection as ExpandedSelection;
          expect(sel.anchor.blockId, 'b');
          expect(sel.focus.blockId, 'a');
          expect(sel.focus.offset, 5);
        },
      );
    },
  );
}
