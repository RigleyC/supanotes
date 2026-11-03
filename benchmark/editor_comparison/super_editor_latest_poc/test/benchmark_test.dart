import 'package:editor_harness/editor_harness.dart';
import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

class SuperEditorDriver extends EditorDriver {
  late final MutableDocument document;
  late final MutableDocumentComposer composer;
  late final Editor editor;
  final focusNode = FocusNode();

  @override
  String get name => 'super_editor(main)';

  @override
  Widget build(List<BlockSpec> blocks) {
    document = MutableDocument(
      nodes: [
        for (var i = 0; i < blocks.length; i++)
          blocks[i].type == BlockType.paragraph
              ? ParagraphNode(id: 'b$i', text: AttributedText(blocks[i].text))
              : TaskNode(
                  id: 'b$i',
                  text: AttributedText(blocks[i].text),
                  isComplete: blocks[i].checked,
                ),
      ],
    );
    composer = MutableDocumentComposer();
    editor = createDefaultDocumentEditor(document: document, composer: composer);
    return SuperEditor(
      editor: editor,
      focusNode: focusNode,
      autofocus: true,
      inputSource: TextInputSource.ime,
    );
  }

  DocumentPosition _pos(int index, int offset) => DocumentPosition(
    nodeId: document.getNodeAt(index)!.id,
    nodePosition: TextNodePosition(offset: offset),
  );

  @override
  void placeCaret(int blockIndex, int offset) => editor.execute([
    ChangeSelectionRequest(
      DocumentSelection.collapsed(position: _pos(blockIndex, offset)),
      SelectionChangeType.placeCaret,
      SelectionReason.userInteraction,
    ),
  ]);

  @override
  void typeCharacter(String character) =>
      editor.execute([InsertCharacterAtCaretRequest(character: character)]);

  @override
  void selectRange(int blockIndex, int start, int end) => editor.execute([
    ChangeSelectionRequest(
      DocumentSelection(base: _pos(blockIndex, start), extent: _pos(blockIndex, end)),
      SelectionChangeType.expandSelection,
      SelectionReason.userInteraction,
    ),
  ]);

  @override
  int get blockCount => document.nodeCount;

  @override
  int blockTextLength(int blockIndex) => blockText(blockIndex).length;

  @override
  String blockText(int blockIndex) =>
      (document.getNodeAt(blockIndex)! as TextNode).text.toPlainText();

  @override
  void dispose() => focusNode.dispose();
}

void main() {
  configureBinding();
  benchmarkEditor(SuperEditorDriver.new);
}
