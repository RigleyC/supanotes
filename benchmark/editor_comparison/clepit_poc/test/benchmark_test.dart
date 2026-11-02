import 'package:clepit_core/clepit_core.dart'
    show
        ChecklistBlock,
        ChecklistData,
        ChecklistItem,
        Editor,
        EditorConfig,
        EditorController,
        EditorData,
        HtmlCodec,
        InlineDocument,
        ParagraphBlock,
        ParagraphData,
        RichTextController,
        Block;
import 'package:editor_harness/editor_harness.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show TextEditingValue, TextInputClient, TextSelection;

/// Drives clepit_core through the same objects a real keystroke and tap reach:
///
/// * caret/selection: the block's `EditableText` takes focus (which is what
///   sets `EditorController.activeRichController`, as a tap does), then the
///   controller's selection is set.
/// * typing: `TextInputClient.updateEditingValue` on that `EditableText`
///   state, which is the method the platform IME calls with the new value.
class ClepitDriver extends EditorDriver {
  late EditorController controller;

  @override
  String get name => 'clepit_core';

  @override
  Widget build(List<BlockSpec> blocks) {
    controller = EditorController(
      initial: EditorData(
        blocks: [
          for (var i = 0; i < blocks.length; i++)
            blocks[i].type == BlockType.paragraph
                ? ParagraphBlock(
                    id: 'p$i',
                    paragraphData: ParagraphData(
                      html: HtmlCodec.encode(InlineDocument(text: blocks[i].text)),
                    ),
                  )
                : ChecklistBlock(
                    id: 't$i',
                    checklistData: ChecklistData(
                      items: [
                        ChecklistItem(
                          text: HtmlCodec.encode(InlineDocument(text: blocks[i].text)),
                          checked: blocks[i].checked,
                        ),
                      ],
                    ),
                  ),
        ],
      ),
    );
    return Editor(controller: controller, config: const EditorConfig());
  }

  /// The block's `EditableText` element, found through the block's own keyed
  /// subtree (`EditorController.blockContentKeys`).
  StatefulElement _editableOf(int blockIndex) {
    final id = controller.store.blocks[blockIndex].id!;
    final root = controller.blockContentKeys[id]!.currentContext! as Element;
    StatefulElement? found;
    void visit(Element e) {
      if (found != null) return;
      if (e.widget is EditableText) {
        found = e as StatefulElement;
        return;
      }
      e.visitChildren(visit);
    }

    visit(root);
    return found!;
  }

  @override
  Future<void> placeCaret(int blockIndex, int offset) =>
      selectRange(blockIndex, offset, offset);

  int _caretBlock = 0;

  /// The list is lazy (`ReorderableListView.builder`), so a block that is
  /// off-screen has no element to take focus. Scroll it in with the package's
  /// own `revealBlock`, as a user would scroll to it. Visible blocks skip this.
  Future<void> _ensureBuilt(int blockIndex) async {
    final id = controller.store.blocks[blockIndex].id!;
    if (controller.blockContentKeys[id]?.currentContext != null) return;
    await controller.revealBlock(id);
  }

  @override
  Future<void> selectRange(int blockIndex, int start, int end) async {
    _caretBlock = blockIndex;
    await _ensureBuilt(blockIndex);
    final element = _editableOf(blockIndex);
    final widget = element.widget as EditableText;
    // A tap focuses the block; the block's focus listener then sets
    // activeRichController. Set it explicitly too, so the caret target does
    // not depend on the focus listener running.
    widget.focusNode.requestFocus();
    controller.activeRichController = widget.controller as RichTextController;
    widget.controller.selection =
        TextSelection(baseOffset: start, extentOffset: end);
  }

  @override
  void typeCharacter(String character) {
    final rich = controller.activeRichController!;
    final sel = rich.selection;
    // The same call the platform makes with the IME's new editing value.
    final client = _editableOf(_caretBlock).state as TextInputClient;
    client.updateEditingValue(TextEditingValue(
      text: rich.text.replaceRange(sel.start, sel.end, character),
      selection: TextSelection.collapsed(offset: sel.start + character.length),
    ));
  }

  @override
  int get blockCount => controller.store.blocks.length;

  @override
  int blockTextLength(int blockIndex) => blockText(blockIndex).length;

  @override
  String blockText(int blockIndex) {
    final Block block = controller.store.blocks[blockIndex];
    final html = switch (block) {
      ParagraphBlock(:final paragraphData) => paragraphData.html,
      ChecklistBlock(:final checklistData) => checklistData.items.single.text,
      _ => throw StateError('unexpected block ${block.type}'),
    };
    return HtmlCodec.decode(html).text;
  }

  @override
  void dispose() => controller.dispose();
}

void main() {
  configureBinding();
  benchmarkEditor(ClepitDriver.new);
}
