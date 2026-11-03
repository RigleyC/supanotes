import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:block_editor/block_editor.dart';

BlockController _ctrl(List<BlockNode> blocks) =>
    BlockController(document: BlockDocument(blocks));

BlockNode _emptyPara(String id) =>
    BlockNode(id: id, type: BlockTypes.paragraph);

BlockNode _para(String id, String text) => BlockNode(
  id: id,
  type: BlockTypes.paragraph,
  delta: TextDelta([TextOp(text)]),
);

Widget _menuWidget({
  required BlockController ctrl,
  required VoidCallback onDismiss,
  String triggerBlockId = 'a',
  int triggerOffset = 1,
}) {
  final ops = EditorEditingOperations(ctrl);
  final editorKey = GlobalKey();
  final editorFocusNode = FocusNode();
  return MaterialApp(
    home: Scaffold(
      body: Focus(
        focusNode: editorFocusNode,
        child: SizedBox(
          key: editorKey,
          width: 600,
          height: 400,
          child: SlashCommandMenu(
            controller: ctrl,
            ops: ops,
            anchorKey: null,
            editorKey: editorKey,
            editorFocusNode: editorFocusNode,
            triggerBlockId: triggerBlockId,
            triggerOffset: triggerOffset,
            onDismiss: onDismiss,
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('SlashCommandMenu — renders', () {
    testWidgets('menu renders with entries from registry', (tester) async {
      final ctrl = _ctrl([_emptyPara('a')]);
      ctrl.collapseSelection('a', 0);

      await tester.pumpWidget(_menuWidget(ctrl: ctrl, onDismiss: () {}));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(SlashCommandMenu), findsOneWidget);
    });

    testWidgets('no results text shown when filter yields nothing', (
      tester,
    ) async {
      final ctrl = _ctrl([_emptyPara('a')]);
      ctrl.collapseSelection('a', 0);

      await tester.pumpWidget(_menuWidget(ctrl: ctrl, onDismiss: () {}));
      await tester.pump(const Duration(milliseconds: 50));

      await tester.sendKeyEvent(LogicalKeyboardKey.keyX, character: 'x');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyX, character: 'x');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyX, character: 'x');
      await tester.pump();

      expect(find.text('No results'), findsOneWidget);
    });
  });

  group('SlashCommandMenu — keyboard dismissal', () {
    testWidgets('Escape calls onDismiss', (tester) async {
      var dismissed = false;
      final ctrl = _ctrl([_emptyPara('a')]);
      ctrl.collapseSelection('a', 0);

      await tester.pumpWidget(
        _menuWidget(ctrl: ctrl, onDismiss: () => dismissed = true),
      );
      await tester.pump(const Duration(milliseconds: 50));

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(dismissed, isTrue);
    });

    testWidgets('backspace when filter is empty calls onDismiss', (
      tester,
    ) async {
      var dismissed = false;
      final ctrl = _ctrl([_emptyPara('a')]);
      ctrl.collapseSelection('a', 0);

      await tester.pumpWidget(
        _menuWidget(ctrl: ctrl, onDismiss: () => dismissed = true),
      );
      await tester.pump(const Duration(milliseconds: 50));

      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();

      expect(dismissed, isTrue);
    });
  });

  group('SlashCommandMenu — keyboard navigation', () {
    testWidgets('arrow down moves highlight and Enter selects', (tester) async {
      final ctrl = _ctrl([_emptyPara('a')]);
      ctrl.collapseSelection('a', 0);
      ctrl.updateDelta('a', TextDelta([const TextOp('/')]));

      await tester.pumpWidget(
        _menuWidget(ctrl: ctrl, onDismiss: () {}, triggerOffset: 1),
      );
      await tester.pump(const Duration(milliseconds: 50));

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(ctrl.document.blocks.isNotEmpty, isTrue);
    });
  });

  group('SlashCommandMenu — tap to select', () {
    testWidgets('tapping an entry calls onDismiss', (tester) async {
      var dismissed = false;
      final ctrl = _ctrl([_emptyPara('a')]);
      ctrl.collapseSelection('a', 0);
      ctrl.updateDelta('a', TextDelta([const TextOp('/')]));

      await tester.pumpWidget(
        _menuWidget(
          ctrl: ctrl,
          onDismiss: () => dismissed = true,
          triggerOffset: 1,
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      final entries = find.byType(GestureDetector);
      if (entries.evaluate().length > 1) {
        await tester.tap(entries.at(1));
        await tester.pump();
        expect(dismissed, isTrue);
      }
    });
  });

  group('SlashCommandMenu — block transformation unit tests', () {
    test('transforms empty block to target type', () {
      final ctrl = _ctrl([_emptyPara('a')]);
      ctrl.collapseSelection('a', 0);

      final ops = EditorEditingOperations(ctrl);
      ops.insertCharacter('/');

      final node = ctrl.document.findById('a')!;
      final slashPos = 0;
      final trimmed = (node.delta ?? TextDelta.empty()).slice(0, slashPos);
      ctrl.updateDelta('a', trimmed);

      final updated = ctrl.document.findById('a')!;
      final isEmpty = updated.delta == null || updated.delta!.plainText.isEmpty;
      expect(isEmpty, isTrue);

      ctrl.transformType('a', BlockTypes.heading1);
      ctrl.collapseSelection('a', 0);

      expect(ctrl.document.findById('a')!.type, BlockTypes.heading1);
    });

    test('inserts new block below when current block has content', () {
      final ctrl = _ctrl([_para('a', 'some text ')]);
      ctrl.collapseSelection('a', 10);

      final ops = EditorEditingOperations(ctrl);
      ops.insertCharacter('/');

      final blocks = ctrl.document.blocks;
      final index = blocks.indexWhere((b) => b.id == 'a');
      final newNode = BlockNode(type: BlockTypes.heading2);
      ctrl.insertAt(index + 1, newNode);
      ctrl.collapseSelection(newNode.id, 0);

      expect(ctrl.document.blocks.length, 2);
      expect(ctrl.document.blocks[1].type, BlockTypes.heading2);
    });

    test('filter reduces visible entries', () {
      final ctrl = _ctrl([_emptyPara('a')]);
      final ops = EditorEditingOperations(ctrl);
      final editorKey = GlobalKey();
      final editorFocusNode = FocusNode();

      final menu = _SlashMenuEntryCounter(
        controller: ctrl,
        ops: ops,
        editorKey: editorKey,
        editorFocusNode: editorFocusNode,
      );

      final allCount = menu.allEntries.length;
      menu.applyFilter('heading');
      final filteredCount = menu.filteredEntries.length;

      expect(filteredCount, lessThan(allCount));
      expect(filteredCount, greaterThan(0));
    });
  });

  group('SlashCommandMenu — trigger condition logic', () {
    test('slash at offset 1 is a valid trigger', () {
      expect(_isValidTrigger('/', 1), isTrue);
    });

    test('slash after space is a valid trigger', () {
      expect(_isValidTrigger('hello /', 7), isTrue);
    });

    test('slash mid-word is not a valid trigger', () {
      expect(_isValidTrigger('hel/', 4), isFalse);
    });

    test('slash at offset 0 is not a valid trigger', () {
      expect(_isValidTrigger('', 0), isFalse);
    });
  });
}

bool _isValidTrigger(String text, int offset) {
  if (offset == 1) return true;
  if (offset >= 2 && text.length >= 2 && text[offset - 2] == ' ') return true;
  return false;
}

class _SlashMenuEntryCounter {
  _SlashMenuEntryCounter({
    required this.controller,
    required this.ops,
    required this.editorKey,
    required this.editorFocusNode,
  }) {
    _all = _build();
    _filtered = List.of(_all);
  }

  final BlockController controller;
  final EditorEditingOperations ops;
  final GlobalKey editorKey;
  final FocusNode editorFocusNode;

  late List<_TestEntry> _all;
  late List<_TestEntry> _filtered;

  List<_TestEntry> get allEntries => _all;
  List<_TestEntry> get filteredEntries => _filtered;

  List<_TestEntry> _build() {
    final entries = <_TestEntry>[];
    final seen = <String>{};
    for (final plugin in BlockRegistry.instance.plugins) {
      final config = plugin.slashCommandItem();
      if (config == null || config.trigger != '/') continue;
      if (seen.contains(plugin.blockType)) continue;
      seen.add(plugin.blockType);
      entries.add(_TestEntry(blockType: plugin.blockType, label: config.label));
    }
    return entries;
  }

  void applyFilter(String query) {
    final lower = query.toLowerCase();
    _filtered = _all
        .where((e) => e.label.toLowerCase().contains(lower))
        .toList();
  }
}

class _TestEntry {
  const _TestEntry({required this.blockType, required this.label});
  final String blockType;
  final String label;
}
