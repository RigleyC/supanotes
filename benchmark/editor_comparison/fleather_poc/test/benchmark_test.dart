import 'package:editor_harness/editor_harness.dart';
import 'package:fleather/fleather.dart';
import 'package:flutter/material.dart';
// Fleather's checkbox/theme/editor look up material_ui's Material, not Flutter's.
import 'package:material_ui/material_ui.dart' as mui;

class FleatherDriver extends EditorDriver {
  late final FleatherController controller;
  final focusNode = FocusNode();
  final scrollController = ScrollController();

  @override
  String get name => 'fleather';

  @override
  Widget build(List<BlockSpec> blocks) {
    final delta = Delta();
    for (final block in blocks) {
      delta.insert(block.text);
      if (block.type == BlockType.task) {
        // Checklist = line-level block attribute 'cl'; checked is a line attribute.
        final style = ParchmentStyle().put(ParchmentAttribute.block.checkList);
        if (block.checked) style.put(ParchmentAttribute.checked);
        delta.insert('\n', style.toJson());
      } else {
        delta.insert('\n');
      }
    }
    controller = FleatherController(
      document: ParchmentDocument.fromDelta(delta),
    );
    return mui.Material(
      type: mui.MaterialType.transparency,
      child: FleatherEditor(
        controller: controller,
        focusNode: focusNode,
        scrollController: scrollController,
        autofocus: true,
        expands: true,
        padding: const EdgeInsets.all(16),
      ),
    );
  }

  /// Lines in document order. Parchment nests consecutive block-scoped lines
  /// (checklists) inside a BlockNode, so flatten one level.
  List<LineNode> get _lines {
    final lines = <LineNode>[];
    for (final child in controller.document.root.children) {
      if (child is LineNode) {
        lines.add(child);
      } else if (child is BlockNode) {
        for (final line in child.children) {
          if (line is LineNode) lines.add(line);
        }
      }
    }
    return lines;
  }

  /// Document offset of the first character of line [blockIndex].
  int _lineStart(int blockIndex) {
    final lines = _lines;
    var offset = 0;
    for (var i = 0; i < blockIndex; i++) {
      offset += lines[i].length; // LineNode.length includes the '\n'
    }
    return offset;
  }

  @override
  void placeCaret(int blockIndex, int offset) =>
      controller.updateSelection(
        TextSelection.collapsed(offset: _lineStart(blockIndex) + offset),
        source: ChangeSource.local,
      );

  @override
  void typeCharacter(String character) {
    // Same entry point the IME path uses (EditorInputClientMixin
    // .updateEditingValueWithDeltas -> controller.replaceText).
    final index = controller.selection.baseOffset;
    controller.replaceText(
      index,
      0,
      character,
      selection: TextSelection.collapsed(offset: index + character.length),
    );
  }

  @override
  void selectRange(int blockIndex, int start, int end) {
    final base = _lineStart(blockIndex);
    controller.updateSelection(
      TextSelection(baseOffset: base + start, extentOffset: base + end),
      source: ChangeSource.local,
    );
  }

  @override
  int get blockCount => _lines.length;

  @override
  int blockTextLength(int blockIndex) => _lines[blockIndex].length - 1;

  @override
  String blockText(int blockIndex) {
    final text = _lines[blockIndex].toPlainText();
    return text.substring(0, text.length - 1); // drop trailing '\n'
  }

  @override
  void dispose() {
    controller.dispose();
    focusNode.dispose();
    scrollController.dispose();
  }
}

void main() {
  configureBinding();
  benchmarkEditor(FleatherDriver.new);
}
