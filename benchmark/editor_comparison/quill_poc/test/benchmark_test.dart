import 'package:editor_harness/editor_harness.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';

class QuillDriver extends EditorDriver {
  late final QuillController controller;
  final focusNode = FocusNode();
  final scrollController = ScrollController();

  @override
  String get name => 'flutter_quill';

  @override
  Widget build(List<BlockSpec> blocks) {
    final delta = Delta();
    for (final block in blocks) {
      delta.insert(block.text);
      delta.insert(
        '\n',
        block.type == BlockType.task
            ? {'list': block.checked ? 'checked' : 'unchecked'}
            : null,
      );
    }
    controller = QuillController(
      document: Document.fromDelta(delta),
      selection: const TextSelection.collapsed(offset: 0),
    );
    return QuillEditor(
      controller: controller,
      focusNode: focusNode,
      scrollController: scrollController,
      config: const QuillEditorConfig(
        autoFocus: true,
        expands: true,
        padding: EdgeInsets.all(16),
      ),
    );
  }

  /// Plain text split per line; each line is followed by '\n' in the document.
  List<String> get _lines => controller.document.toPlainText().split('\n');

  int _lineStart(int blockIndex) {
    final lines = _lines;
    var offset = 0;
    for (var i = 0; i < blockIndex; i++) {
      offset += lines[i].length + 1;
    }
    return offset;
  }

  @override
  void placeCaret(int blockIndex, int offset) =>
      controller.updateSelection(
        TextSelection.collapsed(offset: _lineStart(blockIndex) + offset),
        ChangeSource.local,
      );

  @override
  void typeCharacter(String character) {
    final index = controller.selection.baseOffset;
    controller.replaceText(
      index,
      0,
      character,
      TextSelection.collapsed(offset: index + character.length),
    );
  }

  @override
  void selectRange(int blockIndex, int start, int end) {
    final base = _lineStart(blockIndex);
    controller.updateSelection(
      TextSelection(baseOffset: base + start, extentOffset: base + end),
      ChangeSource.local,
    );
  }

  @override
  int get blockCount => _lines.length - 1; // trailing '\n' yields one empty entry

  @override
  int blockTextLength(int blockIndex) => blockText(blockIndex).length;

  @override
  String blockText(int blockIndex) => _lines[blockIndex];

  @override
  void dispose() {
    controller.dispose();
    focusNode.dispose();
    scrollController.dispose();
  }
}

void main() {
  configureBinding();
  benchmarkEditor(QuillDriver.new);
}
