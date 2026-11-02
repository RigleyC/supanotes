import 'package:block_editor/block_editor.dart';
import 'package:editor_harness/editor_harness.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Drives `BlockEditorWidget` (block_editor 0.0.4-dev.1).
///
/// Build note: 0.0.4-dev.1 does not compile on Flutter 3.47 (its state class
/// lacks `TextInputClient.onFocusReceived`). `vendor/block_editor` is the
/// pub.dev tarball plus that one override (`=> false`), wired in pubspec.yaml
/// via dependency_overrides. Nothing else in the package was changed.
///
/// Typing goes through the platform text-input channel: the widget attaches a
/// `TextInputConnection`, and `TestTextInput.updateEditingValue` delivers a
/// `TextInputClient.updateEditingState` message to it, exactly like an IME
/// commit. The widget then diffs the value and calls
/// `BlockController.updateDelta` (see `_applyTextChange`).
class BlockEditorDriver extends EditorDriver {
  late BlockController controller;
  FocusNode? _editorFocus;

  @override
  String get name => 'block_editor';

  @override
  Widget build(List<BlockSpec> blocks) {
    controller = BlockController(
      document: BlockDocument([
        for (final b in blocks)
          switch (b.type) {
            BlockType.paragraph => BlockNode(
              type: BlockTypes.paragraph,
              delta: TextDelta([TextOp(b.text)]),
            ),
            BlockType.task => BlockNode(
              type: BlockTypes.todo,
              attributes: {'checked': b.checked},
              delta: TextDelta([TextOp(b.text)]),
            ),
          },
      ]),
    );
    return BlockEditorWidget(controller: controller);
  }

  /// The editor's own `Focus` node (the only one with an `onKeyEvent`
  /// handler inside the BlockEditorWidget subtree).
  FocusNode? _findEditorFocus() {
    if (_editorFocus != null && _editorFocus!.context != null) {
      return _editorFocus;
    }
    for (final node in FocusManager.instance.rootScope.descendants) {
      final ctx = node.context;
      if (node.onKeyEvent != null &&
          ctx != null &&
          ctx.findAncestorWidgetOfExactType<BlockEditorWidget>() != null) {
        return _editorFocus = node;
      }
    }
    return null;
  }

  void _ensureFocused() {
    final node = _findEditorFocus();
    if (node != null && !node.hasFocus) node.requestFocus();
  }

  @override
  void placeCaret(int blockIndex, int offset) {
    controller.collapseSelection(
      controller.document.blocks[blockIndex].id,
      offset,
    );
    // Gaining focus opens the text-input connection (BlockEditorWidget's
    // _onFocusChange -> _openIMEConnection), which typing depends on.
    _ensureFocused();
  }

  @override
  Future<void> typeCharacter(String character) async {
    final sel = controller.selection;
    if (sel is! CollapsedSelection) {
      throw StateError('typeCharacter needs a collapsed caret');
    }
    final node = controller.document.findById(sel.point.blockId)!;
    final text = node.delta?.plainText ?? '';
    final offset = sel.point.offset.clamp(0, text.length);
    final newText =
        text.substring(0, offset) + character + text.substring(offset);
    // Same message a platform IME sends for a committed character.
    TestWidgetsFlutterBinding.instance.testTextInput.updateEditingValue(
      TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: offset + character.length),
      ),
    );
    await Future<void>.value();
  }

  @override
  void selectRange(int blockIndex, int start, int end) {
    final id = controller.document.blocks[blockIndex].id;
    controller.updateSelection(
      ExpandedSelection(
        anchor: SelectionPoint(blockId: id, offset: start),
        focus: SelectionPoint(blockId: id, offset: end),
      ),
    );
  }

  @override
  int get blockCount => controller.document.blocks.length;

  @override
  int blockTextLength(int blockIndex) => blockText(blockIndex).length;

  @override
  String blockText(int blockIndex) =>
      controller.document.blocks[blockIndex].delta?.plainText ?? '';

  @override
  void dispose() => controller.dispose();
}

void main() {
  configureBinding();
  benchmarkEditor(BlockEditorDriver.new);
}
