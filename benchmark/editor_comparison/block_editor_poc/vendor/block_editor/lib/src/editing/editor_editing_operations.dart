library;

import 'package:block_editor/block_editor.dart';

/// Performs all character-level editing operations on a [BlockController].
///
/// [EditorEditingOperations] is a pure-Dart helper with no Flutter dependency.
/// [BlockEditorWidget] holds one instance and delegates all keyboard editing
/// events to it. Every method is independently testable without a widget tree.
///
/// All operations manipulate [TextDelta.ops] directly, preserving inline
/// formatting across every insertion, deletion, and block split.
///
/// When a formatting shortcut such as [applyBold] is invoked with no active
/// [ExpandedSelection], the attribute is stored as a pending attribute.
/// The next call to [insertCharacter] applies all pending attributes to the
/// inserted character and clears them.
class EditorEditingOperations {
  /// Creates an [EditorEditingOperations] bound to [controller].
  EditorEditingOperations(this.controller);

  /// The controller whose document and selection are mutated.
  final BlockController controller;

  InlineAttributes _pending = const InlineAttributes();

  /// Inserts [character] at the current cursor position.
  ///
  /// Inherits [InlineAttributes] from the character immediately to the left,
  /// merged with any pending attributes set by formatting shortcuts. Pending
  /// attributes are cleared after each insertion. Does nothing when the
  /// current selection is not a [CollapsedSelection] or [character] is empty.
  void insertCharacter(String character) {
    if (character.isEmpty) return;
    final sel = controller.selection;
    if (sel is! CollapsedSelection) return;
    final blockId = sel.point.blockId;
    final offset = sel.point.offset;
    final node = controller.document.findById(blockId);
    if (node == null) return;
    final delta = node.delta ?? TextDelta.empty();
    final baseAttrs = _attributesAtOffset(delta.ops, offset);
    final mergedAttrs = _mergePending(baseAttrs);
    final newOps = _insertIntoOps(delta.ops, offset, character, mergedAttrs);
    _pending = const InlineAttributes();
    controller.updateDelta(blockId, TextDelta(newOps));
    controller.collapseSelection(blockId, offset + character.length);
  }

  /// Deletes the character before the cursor or the selected range.
  void backspace() {
    final sel = controller.selection;
    if (sel is ExpandedSelection) {
      _deleteSelectedRange(sel);
      return;
    }
    if (sel is! CollapsedSelection) return;
    final blockId = sel.point.blockId;
    final offset = sel.point.offset;
    final node = controller.document.findById(blockId);
    if (node == null) return;
    if (offset > 0) {
      final delta = node.delta ?? TextDelta.empty();
      final newOps = _deleteRangeFromOps(delta.ops, offset - 1, offset);
      controller.updateDelta(blockId, TextDelta(newOps));
      controller.collapseSelection(blockId, offset - 1);
      return;
    }
    final blocks = controller.document.blocks;
    final index = blocks.indexWhere((b) => b.id == blockId);
    if (index == 0) return;
    final prevNode = blocks[index - 1];
    if (prevNode.delta == null) return;
    final prevDelta = prevNode.delta!;
    final joinOffset = prevDelta.plainText.length;
    final thisDelta = node.delta ?? TextDelta.empty();
    controller.updateDelta(prevNode.id, prevDelta.concat(thisDelta));
    controller.delete(blockId);
    controller.collapseSelection(prevNode.id, joinOffset);
  }

  /// Deletes the character at the cursor or the selected range.
  void delete() {
    final sel = controller.selection;
    if (sel is ExpandedSelection) {
      _deleteSelectedRange(sel);
      return;
    }
    if (sel is! CollapsedSelection) return;
    final blockId = sel.point.blockId;
    final offset = sel.point.offset;
    final node = controller.document.findById(blockId);
    if (node == null) return;
    final delta = node.delta ?? TextDelta.empty();
    if (offset < delta.plainText.length) {
      final newOps = _deleteRangeFromOps(delta.ops, offset, offset + 1);
      controller.updateDelta(blockId, TextDelta(newOps));
      controller.collapseSelection(blockId, offset);
      return;
    }
    final blocks = controller.document.blocks;
    final index = blocks.indexWhere((b) => b.id == blockId);
    if (index == blocks.length - 1) return;
    final nextNode = blocks[index + 1];
    final nextDelta = nextNode.delta ?? TextDelta.empty();
    controller.updateDelta(blockId, delta.concat(nextDelta));
    controller.delete(nextNode.id);
    controller.collapseSelection(blockId, offset);
  }

  /// Splits the current block at the cursor or transforms an empty list block.
  void insertNewline() {
    final sel = controller.selection;
    if (sel is! CollapsedSelection) return;
    final blockId = sel.point.blockId;
    final offset = sel.point.offset;
    final node = controller.document.findById(blockId);
    if (node == null) return;
    final delta = node.delta ?? TextDelta.empty();
    final isListType = _isListType(node.type);
    if (isListType && delta.isEmpty) {
      controller.transformType(blockId, BlockTypes.paragraph);
      controller.collapseSelection(blockId, 0);
      return;
    }
    final isHeading =
        node.type == BlockTypes.heading1 ||
        node.type == BlockTypes.heading2 ||
        node.type == BlockTypes.heading3;
    final newType = isHeading ? BlockTypes.paragraph : node.type;
    final length = delta.plainText.length;
    final before = delta.slice(0, offset);
    final after = delta.slice(offset, length);
    controller.updateDelta(blockId, before);
    final newNode = BlockNode(
      type: newType,
      attributes: isHeading
          ? const {}
          : (Map.of(node.attributes)..remove('checked')),
      delta: after,
    );
    final blocks = controller.document.blocks;
    final index = blocks.indexWhere((b) => b.id == blockId);
    controller.insertAt(index + 1, newNode);
    controller.collapseSelection(newNode.id, 0);
  }

  /// Increments the indent level of the current list block by 1.
  void indent() {
    final sel = controller.selection;
    if (sel is! CollapsedSelection) return;
    final node = controller.document.findById(sel.point.blockId);
    if (node == null || !_isListType(node.type)) return;
    final current = node.attributes['indent'] as int? ?? 0;
    controller.updateAttributes(node.id, {'indent': (current + 1).clamp(0, 8)});
  }

  /// Decrements the indent level of the current list block by 1.
  void dedent() {
    final sel = controller.selection;
    if (sel is! CollapsedSelection) return;
    final node = controller.document.findById(sel.point.blockId);
    if (node == null || !_isListType(node.type)) return;
    final current = node.attributes['indent'] as int? ?? 0;
    controller.updateAttributes(node.id, {'indent': (current - 1).clamp(0, 8)});
  }

  /// Applies bold to the selection or stores it as a pending attribute.
  void applyBold() => _applyOrPend(const InlineAttributes(bold: true));

  /// Applies italic to the selection or stores it as a pending attribute.
  void applyItalic() => _applyOrPend(const InlineAttributes(italic: true));

  /// Applies underline to the selection or stores it as a pending attribute.
  void applyUnderline() =>
      _applyOrPend(const InlineAttributes(underline: true));

  /// Applies strikethrough to the selection or stores it as a pending attribute.
  void applyStrikethrough() =>
      _applyOrPend(const InlineAttributes(strikethrough: true));

  /// Applies inline code to the selection or stores it as a pending attribute.
  void applyInlineCode() =>
      _applyOrPend(const InlineAttributes(inlineCode: true));

  /// Applies link to the selection or stores it as a pending attribute.
  void applyLink(String? link) =>
      _applyOrPend(InlineAttributes(link: link ?? ''));

  /// Applies [attributes] to the current expanded selection.
  ///
  /// Does nothing when the selection is collapsed.
  void applyAttributes(InlineAttributes attributes) => _applyOrPend(attributes);

  /// Moves the cursor to the start of the current block.
  void moveToLineStart() {
    final sel = controller.selection;
    if (sel is! CollapsedSelection) return;
    controller.collapseSelection(sel.point.blockId, 0);
  }

  /// Moves the cursor to the end of the current block.
  void moveToLineEnd() {
    final sel = controller.selection;
    if (sel is! CollapsedSelection) return;
    final node = controller.document.findById(sel.point.blockId);
    if (node == null) return;
    controller.collapseSelection(
      sel.point.blockId,
      node.delta?.plainText.length ?? 0,
    );
  }

  /// Moves the cursor to offset 0 of the first block.
  void moveToDocumentStart() {
    final blocks = controller.document.blocks;
    if (blocks.isEmpty) return;
    controller.collapseSelection(blocks.first.id, 0);
  }

  /// Moves the cursor to the last offset of the last block.
  void moveToDocumentEnd() {
    final blocks = controller.document.blocks;
    if (blocks.isEmpty) return;
    final last = blocks.last;
    controller.collapseSelection(last.id, last.delta?.plainText.length ?? 0);
  }

  /// Moves the cursor one word to the left.
  void moveWordLeft() {
    final sel = controller.selection;
    if (sel is! CollapsedSelection) return;
    final blockId = sel.point.blockId;
    final offset = sel.point.offset;
    final node = controller.document.findById(blockId);
    if (node == null) return;
    final text = node.delta?.plainText ?? '';
    if (offset == 0) {
      final blocks = controller.document.blocks;
      final index = blocks.indexWhere((b) => b.id == blockId);
      if (index == 0) return;
      final prev = blocks[index - 1];
      controller.collapseSelection(prev.id, prev.delta?.plainText.length ?? 0);
      return;
    }
    controller.collapseSelection(blockId, _prevWordBoundary(text, offset));
  }

  /// Moves the cursor one word to the right.
  void moveWordRight() {
    final sel = controller.selection;
    if (sel is! CollapsedSelection) return;
    final blockId = sel.point.blockId;
    final offset = sel.point.offset;
    final node = controller.document.findById(blockId);
    if (node == null) return;
    final text = node.delta?.plainText ?? '';
    if (offset >= text.length) {
      final blocks = controller.document.blocks;
      final index = blocks.indexWhere((b) => b.id == blockId);
      if (index == blocks.length - 1) return;
      controller.collapseSelection(blocks[index + 1].id, 0);
      return;
    }
    controller.collapseSelection(blockId, _nextWordBoundary(text, offset));
  }

  /// Moves the cursor one character to the left.
  void moveCharLeft() {
    final sel = controller.selection;
    if (sel is ExpandedSelection) {
      final ids = controller.document.flatten().map((b) => b.id).toList();
      final resolved = sel.resolveOrder(ids);
      controller.collapseSelection(
        resolved.start.blockId,
        resolved.start.offset,
      );
      return;
    }
    if (sel is! CollapsedSelection) return;
    final blockId = sel.point.blockId;
    final offset = sel.point.offset;
    if (offset > 0) {
      controller.collapseSelection(blockId, offset - 1);
      return;
    }
    final blocks = controller.document.flatten();
    final index = blocks.indexWhere((b) => b.id == blockId);
    if (index <= 0) return;
    final prev = blocks[index - 1];
    controller.collapseSelection(prev.id, prev.delta?.plainText.length ?? 0);
  }

  /// Moves the cursor one character to the right.
  void moveCharRight() {
    final sel = controller.selection;
    if (sel is ExpandedSelection) {
      final ids = controller.document.flatten().map((b) => b.id).toList();
      final resolved = sel.resolveOrder(ids);
      controller.collapseSelection(resolved.end.blockId, resolved.end.offset);
      return;
    }
    if (sel is! CollapsedSelection) return;
    final blockId = sel.point.blockId;
    final offset = sel.point.offset;
    final node = controller.document.findById(blockId);
    final length = node?.delta?.plainText.length ?? 0;
    if (offset < length) {
      controller.collapseSelection(blockId, offset + 1);
      return;
    }
    final blocks = controller.document.flatten();
    final index = blocks.indexWhere((b) => b.id == blockId);
    if (index >= blocks.length - 1) return;
    controller.collapseSelection(blocks[index + 1].id, 0);
  }

  /// Moves the cursor to the end of the previous block.
  void moveLineUp() {
    final sel = controller.selection;
    if (sel is ExpandedSelection) {
      final ids = controller.document.flatten().map((b) => b.id).toList();
      final resolved = sel.resolveOrder(ids);
      controller.collapseSelection(
        resolved.start.blockId,
        resolved.start.offset,
      );
      return;
    }
    if (sel is! CollapsedSelection) return;
    _moveToPrevBlockEnd(sel.point.blockId);
  }

  /// Moves the cursor to the start of the next block.
  void moveLineDown() {
    final sel = controller.selection;
    if (sel is ExpandedSelection) {
      final ids = controller.document.flatten().map((b) => b.id).toList();
      final resolved = sel.resolveOrder(ids);
      controller.collapseSelection(resolved.end.blockId, resolved.end.offset);
      return;
    }
    if (sel is! CollapsedSelection) return;
    _moveToNextBlockStart(sel.point.blockId);
  }

  void _moveToPrevBlockEnd(String blockId) {
    final blocks = controller.document.flatten();
    final index = blocks.indexWhere((b) => b.id == blockId);
    if (index <= 0) return;
    final prev = blocks[index - 1];
    controller.collapseSelection(prev.id, prev.delta?.plainText.length ?? 0);
  }

  void _moveToNextBlockStart(String blockId) {
    final blocks = controller.document.flatten();
    final index = blocks.indexWhere((b) => b.id == blockId);
    if (index >= blocks.length - 1) return;
    controller.collapseSelection(blocks[index + 1].id, 0);
  }

  /// Extends the selection one character to the left.
  void extendSelectionLeft() {
    final sel = controller.selection;
    final anchor = _anchorPoint(sel);
    if (anchor == null) return;
    final focus = _focusPoint(sel);
    if (focus == null) return;
    if (focus.offset > 0) {
      controller.updateSelection(
        ExpandedSelection(
          anchor: anchor,
          focus: SelectionPoint(
            blockId: focus.blockId,
            offset: focus.offset - 1,
          ),
        ),
      );
      return;
    }
    final blocks = controller.document.flatten();
    final index = blocks.indexWhere((b) => b.id == focus.blockId);
    if (index <= 0) return;
    final prev = blocks[index - 1];
    controller.updateSelection(
      ExpandedSelection(
        anchor: anchor,
        focus: SelectionPoint(
          blockId: prev.id,
          offset: prev.delta?.plainText.length ?? 0,
        ),
      ),
    );
  }

  /// Extends the selection one character to the right.
  void extendSelectionRight() {
    final sel = controller.selection;
    final anchor = _anchorPoint(sel);
    if (anchor == null) return;
    final focus = _focusPoint(sel);
    if (focus == null) return;
    final node = controller.document.findById(focus.blockId);
    final length = node?.delta?.plainText.length ?? 0;
    if (focus.offset < length) {
      controller.updateSelection(
        ExpandedSelection(
          anchor: anchor,
          focus: SelectionPoint(
            blockId: focus.blockId,
            offset: focus.offset + 1,
          ),
        ),
      );
      return;
    }
    final blocks = controller.document.flatten();
    final index = blocks.indexWhere((b) => b.id == focus.blockId);
    if (index >= blocks.length - 1) return;
    final next = blocks[index + 1];
    controller.updateSelection(
      ExpandedSelection(
        anchor: anchor,
        focus: SelectionPoint(blockId: next.id, offset: 0),
      ),
    );
  }

  /// Extends the selection up one block.
  void extendSelectionUp() {
    final sel = controller.selection;
    final anchor = _anchorPoint(sel);
    if (anchor == null) return;
    final focus = _focusPoint(sel);
    if (focus == null) return;
    final blocks = controller.document.flatten();
    final index = blocks.indexWhere((b) => b.id == focus.blockId);
    if (index <= 0) return;
    final prev = blocks[index - 1];
    controller.updateSelection(
      ExpandedSelection(
        anchor: anchor,
        focus: SelectionPoint(
          blockId: prev.id,
          offset: prev.delta?.plainText.length ?? 0,
        ),
      ),
    );
  }

  /// Extends the selection down one block.
  void extendSelectionDown() {
    final sel = controller.selection;
    final anchor = _anchorPoint(sel);
    if (anchor == null) return;
    final focus = _focusPoint(sel);
    if (focus == null) return;
    final blocks = controller.document.flatten();
    final index = blocks.indexWhere((b) => b.id == focus.blockId);
    if (index >= blocks.length - 1) return;
    final next = blocks[index + 1];
    controller.updateSelection(
      ExpandedSelection(
        anchor: anchor,
        focus: SelectionPoint(
          blockId: next.id,
          offset: next.delta?.plainText.length ?? 0,
        ),
      ),
    );
  }

  /// Extends the selection to the start of the focus block.
  void extendSelectionToLineStart() {
    final sel = controller.selection;
    final anchor = _anchorPoint(sel);
    if (anchor == null) return;
    final focus = _focusPoint(sel);
    if (focus == null) return;
    controller.updateSelection(
      ExpandedSelection(
        anchor: anchor,
        focus: SelectionPoint(blockId: focus.blockId, offset: 0),
      ),
    );
  }

  /// Extends the selection to the end of the focus block.
  void extendSelectionToLineEnd() {
    final sel = controller.selection;
    final anchor = _anchorPoint(sel);
    if (anchor == null) return;
    final focus = _focusPoint(sel);
    if (focus == null) return;
    final node = controller.document.findById(focus.blockId);
    final length = node?.delta?.plainText.length ?? 0;
    controller.updateSelection(
      ExpandedSelection(
        anchor: anchor,
        focus: SelectionPoint(blockId: focus.blockId, offset: length),
      ),
    );
  }

  /// Extends the selection to offset 0 of the first block.
  void extendSelectionToDocumentStart() {
    final sel = controller.selection;
    final anchor = _anchorPoint(sel);
    if (anchor == null) return;
    final blocks = controller.document.blocks;
    if (blocks.isEmpty) return;
    controller.updateSelection(
      ExpandedSelection(
        anchor: anchor,
        focus: SelectionPoint(blockId: blocks.first.id, offset: 0),
      ),
    );
  }

  /// Extends the selection to the last offset of the last block.
  void extendSelectionToDocumentEnd() {
    final sel = controller.selection;
    final anchor = _anchorPoint(sel);
    if (anchor == null) return;
    final blocks = controller.document.blocks;
    if (blocks.isEmpty) return;
    final last = blocks.last;
    controller.updateSelection(
      ExpandedSelection(
        anchor: anchor,
        focus: SelectionPoint(
          blockId: last.id,
          offset: last.delta?.plainText.length ?? 0,
        ),
      ),
    );
  }

  /// Extends the selection one word to the left.
  void extendSelectionWordLeft() {
    final sel = controller.selection;
    final anchor = _anchorPoint(sel);
    if (anchor == null) return;
    final focus = _focusPoint(sel);
    if (focus == null) return;
    final blockId = focus.blockId;
    final offset = focus.offset;
    final node = controller.document.findById(blockId);
    final text = node?.delta?.plainText ?? '';
    if (offset == 0) {
      final blocks = controller.document.flatten();
      final index = blocks.indexWhere((b) => b.id == blockId);
      if (index <= 0) return;
      final prev = blocks[index - 1];
      controller.updateSelection(
        ExpandedSelection(
          anchor: anchor,
          focus: SelectionPoint(
            blockId: prev.id,
            offset: prev.delta?.plainText.length ?? 0,
          ),
        ),
      );
      return;
    }
    controller.updateSelection(
      ExpandedSelection(
        anchor: anchor,
        focus: SelectionPoint(
          blockId: blockId,
          offset: _prevWordBoundary(text, offset),
        ),
      ),
    );
  }

  /// Extends the selection one word to the right.
  void extendSelectionWordRight() {
    final sel = controller.selection;
    final anchor = _anchorPoint(sel);
    if (anchor == null) return;
    final focus = _focusPoint(sel);
    if (focus == null) return;
    final blockId = focus.blockId;
    final offset = focus.offset;
    final node = controller.document.findById(blockId);
    final text = node?.delta?.plainText ?? '';
    if (offset >= text.length) {
      final blocks = controller.document.flatten();
      final index = blocks.indexWhere((b) => b.id == blockId);
      if (index >= blocks.length - 1) return;
      controller.updateSelection(
        ExpandedSelection(
          anchor: anchor,
          focus: SelectionPoint(blockId: blocks[index + 1].id, offset: 0),
        ),
      );
      return;
    }
    controller.updateSelection(
      ExpandedSelection(
        anchor: anchor,
        focus: SelectionPoint(
          blockId: blockId,
          offset: _nextWordBoundary(text, offset),
        ),
      ),
    );
  }

  SelectionPoint? _anchorPoint(EditorSelection sel) {
    if (sel is CollapsedSelection) return sel.point;
    if (sel is ExpandedSelection) return sel.anchor;
    return null;
  }

  SelectionPoint? _focusPoint(EditorSelection sel) {
    if (sel is CollapsedSelection) return sel.point;
    if (sel is ExpandedSelection) return sel.focus;
    return null;
  }

  void _applyOrPend(InlineAttributes attributes) {
    final sel = controller.selection;
    if (sel is ExpandedSelection) {
      _applyInline(attributes);
    } else if (sel is CollapsedSelection) {
      _pending = _mergeIntoAttributes(_pending, attributes);
    }
  }

  InlineAttributes _mergeIntoAttributes(
    InlineAttributes base,
    InlineAttributes overlay,
  ) {
    return InlineAttributes(
      bold: overlay.bold ?? base.bold,
      italic: overlay.italic ?? base.italic,
      underline: overlay.underline ?? base.underline,
      strikethrough: overlay.strikethrough ?? base.strikethrough,
      inlineCode: overlay.inlineCode ?? base.inlineCode,
      link: overlay.link ?? base.link,
      color: overlay.color ?? base.color,
      backgroundColor: overlay.backgroundColor ?? base.backgroundColor,
    );
  }

  InlineAttributes _mergePending(InlineAttributes base) {
    if (_pending.isEmpty) return base;
    return _mergeIntoAttributes(base, _pending);
  }

  List<DeltaOp> _insertIntoOps(
    List<DeltaOp> ops,
    int offset,
    String character,
    InlineAttributes attrs,
  ) {
    if (ops.isEmpty) return [TextOp(character, attributes: attrs)];
    final result = <DeltaOp>[];
    var cursor = 0;
    var inserted = false;
    for (final op in ops) {
      if (op is! TextOp) {
        if (!inserted && cursor == offset) {
          result.add(TextOp(character, attributes: attrs));
          inserted = true;
        }
        result.add(op);
        cursor++;
        continue;
      }
      final opEnd = cursor + op.text.length;
      if (!inserted && offset >= cursor && offset <= opEnd) {
        final splitAt = offset - cursor;
        final before = op.text.substring(0, splitAt);
        final after = op.text.substring(splitAt);
        if (before.isNotEmpty) {
          result.add(TextOp(before, attributes: op.attributes));
        }
        result.add(TextOp(character, attributes: attrs));
        if (after.isNotEmpty) {
          result.add(TextOp(after, attributes: op.attributes));
        }
        inserted = true;
      } else {
        result.add(op);
      }
      cursor = opEnd;
    }
    if (!inserted) result.add(TextOp(character, attributes: attrs));
    return result;
  }

  List<DeltaOp> _deleteRangeFromOps(List<DeltaOp> ops, int start, int end) {
    final result = <DeltaOp>[];
    var cursor = 0;
    for (final op in ops) {
      if (op is! TextOp) {
        if (cursor < start || cursor >= end) result.add(op);
        cursor++;
        continue;
      }
      final opStart = cursor;
      final opEnd = cursor + op.text.length;
      cursor = opEnd;
      if (opEnd <= start || opStart >= end) {
        result.add(op);
        continue;
      }
      final keepBefore = op.text.substring(
        0,
        (start - opStart).clamp(0, op.text.length),
      );
      final keepAfter = op.text.substring(
        (end - opStart).clamp(0, op.text.length),
      );
      if (keepBefore.isNotEmpty) {
        result.add(TextOp(keepBefore, attributes: op.attributes));
      }
      if (keepAfter.isNotEmpty) {
        result.add(TextOp(keepAfter, attributes: op.attributes));
      }
    }
    return result;
  }

  InlineAttributes _attributesAtOffset(List<DeltaOp> ops, int offset) {
    if (offset == 0 || ops.isEmpty) return const InlineAttributes();
    var cursor = 0;
    for (final op in ops) {
      if (op is! TextOp) {
        cursor++;
        continue;
      }
      final opEnd = cursor + op.text.length;
      if (offset > cursor && offset <= opEnd) return op.attributes;
      cursor = opEnd;
    }
    final last = ops.lastWhere((op) => op is TextOp, orElse: () => ops.last);
    return last is TextOp ? last.attributes : const InlineAttributes();
  }

  void _deleteSelectedRange(ExpandedSelection sel) {
    final ids = controller.document.flatten().map((b) => b.id).toList();
    final resolved = sel.resolveOrder(ids);
    final startId = resolved.start.blockId;
    final endId = resolved.end.blockId;
    final startOffset = resolved.start.offset;
    final endOffset = resolved.end.offset;
    if (startId == endId) {
      final node = controller.document.findById(startId);
      if (node == null) return;
      final delta = node.delta ?? TextDelta.empty();
      final newOps = _deleteRangeFromOps(delta.ops, startOffset, endOffset);
      controller.updateDelta(startId, TextDelta(newOps));
      controller.collapseSelection(startId, startOffset);
      return;
    }
    final startNode = controller.document.findById(startId);
    final endNode = controller.document.findById(endId);
    if (startNode == null || endNode == null) return;
    final startDelta = startNode.delta ?? TextDelta.empty();
    final endDelta = endNode.delta ?? TextDelta.empty();
    final merged = startDelta
        .slice(0, startOffset)
        .concat(endDelta.slice(endOffset, endDelta.plainText.length));
    final allBlocks = controller.document.flatten();
    final startIndex = allBlocks.indexWhere((b) => b.id == startId);
    final endIndex = allBlocks.indexWhere((b) => b.id == endId);
    for (var i = endIndex; i > startIndex; i--) {
      controller.delete(allBlocks[i].id);
    }
    controller.updateDelta(startId, merged);
    controller.collapseSelection(startId, startOffset);
  }

  void _applyInline(InlineAttributes attributes) {
    final sel = controller.selection;
    if (sel is! ExpandedSelection) return;
    final ids = controller.document.flatten().map((b) => b.id).toList();
    final resolved = sel.resolveOrder(ids);
    if (resolved.start.blockId == resolved.end.blockId) {
      controller.applyInlineAttributes(
        resolved.start.blockId,
        resolved.start.offset,
        resolved.end.offset,
        attributes,
      );
      return;
    }
    final startNode = controller.document.findById(resolved.start.blockId);
    if (startNode != null) {
      controller.applyInlineAttributes(
        resolved.start.blockId,
        resolved.start.offset,
        startNode.delta?.plainText.length ?? 0,
        attributes,
      );
    }
    final allBlocks = controller.document.flatten();
    final startIndex = allBlocks.indexWhere(
      (b) => b.id == resolved.start.blockId,
    );
    final endIndex = allBlocks.indexWhere((b) => b.id == resolved.end.blockId);
    for (var i = startIndex + 1; i < endIndex; i++) {
      final node = allBlocks[i];
      final length = node.delta?.plainText.length ?? 0;
      if (length > 0) {
        controller.applyInlineAttributes(node.id, 0, length, attributes);
      }
    }
    controller.applyInlineAttributes(
      resolved.end.blockId,
      0,
      resolved.end.offset,
      attributes,
    );
  }

  bool _isListType(String type) =>
      type == BlockTypes.bulletList ||
      type == BlockTypes.numberedList ||
      type == BlockTypes.todo;

  int _prevWordBoundary(String text, int offset) {
    var i = offset - 1;
    while (i > 0 && _isWhitespace(text[i - 1])) {
      i--;
    }
    while (i > 0 && !_isWhitespace(text[i - 1])) {
      i--;
    }
    return i;
  }

  int _nextWordBoundary(String text, int offset) {
    var i = offset;
    while (i < text.length && _isWhitespace(text[i])) {
      i++;
    }
    while (i < text.length && !_isWhitespace(text[i])) {
      i++;
    }
    return i;
  }

  bool _isWhitespace(String char) => char.trim().isEmpty;
}
