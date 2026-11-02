import 'package:appflowy_editor/appflowy_editor.dart';
// The keyboard service's own insert handler (character shortcuts included).
import 'package:appflowy_editor/src/editor/editor_component/service/ime/delta_input_on_insert_impl.dart';
import 'package:flutter/services.dart';
import 'package:editor_harness/editor_harness.dart';
import 'package:flutter/material.dart';

class AppFlowyDriver extends EditorDriver {
  late EditorState editorState;
  late EditorScrollController scrollController;

  @override
  String get name => _imePath ? 'appflowy_editor(ime-path)' : 'appflowy_editor';

  static const _imePath = bool.fromEnvironment('IME_PATH');

  @override
  Widget build(List<BlockSpec> blocks) {
    editorState = EditorState(
      document: Document(
        root: Node(
          type: 'page',
          children: [
            for (final b in blocks)
              b.type == BlockType.paragraph
                  ? paragraphNode(text: b.text)
                  : todoListNode(checked: b.checked, text: b.text),
          ],
        ),
      ),
    );
    editorState.editable = true;
    scrollController = EditorScrollController(editorState: editorState);
    return AppFlowyEditor(
      editorState: editorState,
      editable: true,
      autoFocus: true,
      editorScrollController: scrollController,
      blockComponentBuilders: standardBlockComponentBuilderMap,
    );
  }

  Position _pos(int index, int offset) =>
      Position(path: [index], offset: offset);

  @override
  Future<void> placeCaret(int blockIndex, int offset) async {
    editorState.selection = Selection.collapsed(_pos(blockIndex, offset));
  }

  @override
  Future<void> typeCharacter(String character) async {
    if (!_imePath) {
      await editorState.insertTextAtCurrentSelection(character);
      return;
    }
    // Same entry point as a keystroke arriving from the platform IME:
    // character shortcut events run first, then the text is inserted.
    await onInsert(
      TextEditingDeltaInsertion(
        oldText: '',
        textInserted: character,
        insertionOffset: 0,
        selection: const TextSelection.collapsed(offset: 1),
        composing: TextRange.empty,
      ),
      editorState,
      standardCharacterShortcutEvents,
    );
  }

  @override
  Future<void> selectRange(int blockIndex, int start, int end) async {
    editorState.selection = Selection.single(
      path: [blockIndex],
      startOffset: start,
      endOffset: end,
    );
  }

  @override
  int get blockCount => editorState.document.root.children.length;

  @override
  int blockTextLength(int blockIndex) => blockText(blockIndex).length;

  @override
  String blockText(int blockIndex) => editorState.document.root.children
      .elementAt(blockIndex)
      .delta!
      .toPlainText();

  @override
  void dispose() {
    scrollController.dispose();
    editorState.dispose();
  }
}

void main() {
  configureBinding();
  benchmarkEditor(AppFlowyDriver.new);
}
