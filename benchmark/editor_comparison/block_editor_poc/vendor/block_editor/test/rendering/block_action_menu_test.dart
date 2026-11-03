import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:block_editor/block_editor.dart';

BlockController _ctrl(List<BlockNode> blocks) =>
    BlockController(document: BlockDocument(blocks));

BlockNode _para(String id, String text) => BlockNode(
  id: id,
  type: BlockTypes.paragraph,
  delta: TextDelta([TextOp(text)]),
);

Widget _menuWidget({
  required BlockController ctrl,
  required String blockId,
  required VoidCallback onDismiss,
}) {
  return MaterialApp(
    home: Scaffold(
      body: BlockActionMenu(
        controller: ctrl,
        blockId: blockId,
        globalPosition: const Offset(100, 100),
        onDismiss: onDismiss,
      ),
    ),
  );
}

void main() {
  group('BlockActionMenu — renders', () {
    testWidgets('shows all five action labels', (tester) async {
      final ctrl = _ctrl([_para('a', 'hello'), _para('b', 'world')]);

      await tester.pumpWidget(
        _menuWidget(ctrl: ctrl, blockId: 'a', onDismiss: () {}),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Delete block'), findsOneWidget);
      expect(find.text('Duplicate block'), findsOneWidget);
      expect(find.text('Turn into'), findsOneWidget);
      expect(find.text('Move up'), findsOneWidget);
      expect(find.text('Move down'), findsOneWidget);
    });
  });

  group('BlockActionMenu — delete', () {
    testWidgets('deletes the block and dismisses', (tester) async {
      var dismissed = false;
      final ctrl = _ctrl([_para('a', 'first'), _para('b', 'second')]);

      await tester.pumpWidget(
        _menuWidget(
          ctrl: ctrl,
          blockId: 'a',
          onDismiss: () => dismissed = true,
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.text('Delete block'));
      await tester.pump();

      expect(ctrl.document.blocks.length, 1);
      expect(ctrl.document.blocks.first.id, 'b');
      expect(dismissed, isTrue);
    });
  });

  group('BlockActionMenu — duplicate', () {
    testWidgets('duplicates the block and dismisses', (tester) async {
      var dismissed = false;
      final ctrl = _ctrl([_para('a', 'hello')]);

      await tester.pumpWidget(
        _menuWidget(
          ctrl: ctrl,
          blockId: 'a',
          onDismiss: () => dismissed = true,
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.text('Duplicate block'));
      await tester.pump();

      expect(ctrl.document.blocks.length, 2);
      expect(ctrl.document.blocks[1].delta?.plainText, 'hello');
      expect(ctrl.document.blocks[1].id, isNot('a'));
      expect(dismissed, isTrue);
    });
  });

  group('BlockActionMenu — move up', () {
    testWidgets('moves block up and dismisses', (tester) async {
      var dismissed = false;
      final ctrl = _ctrl([_para('a', 'first'), _para('b', 'second')]);

      await tester.pumpWidget(
        _menuWidget(
          ctrl: ctrl,
          blockId: 'b',
          onDismiss: () => dismissed = true,
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.text('Move up'));
      await tester.pump();

      expect(ctrl.document.blocks.first.id, 'b');
      expect(dismissed, isTrue);
    });

    testWidgets('move up is disabled for first block', (tester) async {
      final ctrl = _ctrl([_para('a', 'only'), _para('b', 'second')]);

      await tester.pumpWidget(
        _menuWidget(ctrl: ctrl, blockId: 'a', onDismiss: () {}),
      );
      await tester.pump(const Duration(milliseconds: 50));

      final originalOrder = ctrl.document.blocks.map((b) => b.id).toList();
      await tester.tap(find.text('Move up'));
      await tester.pump();

      expect(ctrl.document.blocks.map((b) => b.id).toList(), originalOrder);
    });
  });

  group('BlockActionMenu — move down', () {
    testWidgets('moves block down and dismisses', (tester) async {
      var dismissed = false;
      final ctrl = _ctrl([_para('a', 'first'), _para('b', 'second')]);

      await tester.pumpWidget(
        _menuWidget(
          ctrl: ctrl,
          blockId: 'a',
          onDismiss: () => dismissed = true,
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.text('Move down'));
      await tester.pump();

      expect(ctrl.document.blocks.first.id, 'b');
      expect(dismissed, isTrue);
    });

    testWidgets('move down is disabled for last block', (tester) async {
      final ctrl = _ctrl([_para('a', 'first'), _para('b', 'last')]);

      await tester.pumpWidget(
        _menuWidget(ctrl: ctrl, blockId: 'b', onDismiss: () {}),
      );
      await tester.pump(const Duration(milliseconds: 50));

      final originalOrder = ctrl.document.blocks.map((b) => b.id).toList();
      await tester.tap(find.text('Move down'));
      await tester.pump();

      expect(ctrl.document.blocks.map((b) => b.id).toList(), originalOrder);
    });
  });

  group('BlockActionMenu — turn into', () {
    testWidgets('opens turn into submenu on tap', (tester) async {
      final ctrl = _ctrl([_para('a', 'hello')]);

      await tester.pumpWidget(
        _menuWidget(ctrl: ctrl, blockId: 'a', onDismiss: () {}),
      );
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.text('Turn into'));
      await tester.pump();

      expect(find.byType(ListView), findsWidgets);
    });
  });

  group('BlockActionMenu — escape dismisses', () {
    testWidgets('Escape key calls onDismiss', (tester) async {
      var dismissed = false;
      final ctrl = _ctrl([_para('a', 'hello')]);

      await tester.pumpWidget(
        _menuWidget(
          ctrl: ctrl,
          blockId: 'a',
          onDismiss: () => dismissed = true,
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(dismissed, isTrue);
    });
  });

  group('BlockController — duplicate', () {
    test('inserts copy with new id immediately below original', () {
      final ctrl = _ctrl([_para('a', 'hello'), _para('b', 'world')]);

      ctrl.duplicate('a');

      expect(ctrl.document.blocks.length, 3);
      expect(ctrl.document.blocks[1].delta?.plainText, 'hello');
      expect(ctrl.document.blocks[1].id, isNot('a'));
      expect(ctrl.document.blocks[2].id, 'b');
    });

    test('does nothing when blockId does not exist', () {
      final ctrl = _ctrl([_para('a', 'hello')]);

      ctrl.duplicate('nonexistent');

      expect(ctrl.document.blocks.length, 1);
    });

    test('duplicate preserves block type', () {
      final ctrl = BlockController(
        document: BlockDocument([
          BlockNode(
            id: 'a',
            type: BlockTypes.heading1,
            delta: TextDelta([const TextOp('Title')]),
          ),
        ]),
      );

      ctrl.duplicate('a');

      expect(ctrl.document.blocks[1].type, BlockTypes.heading1);
      expect(ctrl.document.blocks[1].delta?.plainText, 'Title');
    });
  });
}
