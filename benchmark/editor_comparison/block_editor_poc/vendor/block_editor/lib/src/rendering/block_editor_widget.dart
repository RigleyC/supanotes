library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:block_editor/block_editor.dart';

/// The root widget of the block editor.
///
/// [BlockEditorWidget] assembles the full rendering pipeline — block layout,
/// cursor, selection highlight, keyboard routing, scroll, IME input, the
/// context-sensitive formatting toolbar, and the slash command menu — on top
/// of a [BlockController] supplied by the caller.
///
/// The caller owns the [controller] and is responsible for calling
/// [BlockController.dispose] when it is no longer needed.
///
/// Setting [readOnly] to true switches the editor into a clean viewer mode.
/// All editing operations, keyboard shortcuts, IME input, and the formatting
/// toolbar are disabled.
///
/// ## Formatting toolbar display modes
///
/// The toolbar appears whenever the editor has an active [ExpandedSelection]
/// and [readOnly] is false. Its layout adapts to the available screen width
/// compared to [toolbarBreakpoint]:
///
/// - **Wide** (available width ≥ [toolbarBreakpoint]): the toolbar floats
///   above the selected block, horizontally centered and clamped to screen
///   edges.
/// - **Narrow / desktop**: the toolbar is pinned to the bottom of the
///   editor's own bounds.
///
/// ## Color picker
///
/// The toolbar includes text color and background color buttons. Their
/// behavior depends on [onColorPickerRequested]:
///
/// **Zero-config (default, [onColorPickerRequested] is null):**
/// ```dart
/// BlockEditorWidget(controller: controller)
/// ```
/// Tapping either color button opens a built-in 12-swatch palette popover
/// with a clear option. The palette is a private implementation detail of the
/// toolbar and is not part of the public API.
///
/// **Custom color picker ([onColorPickerRequested] is non-null):**
/// ```dart
/// BlockEditorWidget(
///   controller: controller,
///   onColorPickerRequested: (currentColor) async {
///     final picked = await showMyColorPicker(
///       context: context,
///       initialColor: currentColor,
///     );
///     return picked;
///   },
/// )
/// ```
/// The callback receives the current color of the first op in the selection
/// (may be null if no color is set) and must return a [Future<Color?>].
/// When the future resolves to a non-null [Color] that color is applied to
/// the selection. When it resolves to null no change is made. The built-in
/// palette is never shown when this callback is provided.
class BlockEditorWidget extends StatefulWidget {
  const BlockEditorWidget({
    super.key,
    required this.controller,
    this.scrollController,
    this.readOnly = false,
    this.padding = const EdgeInsets.all(16),
    this.cursorColor = const Color(0xFF000000),
    this.selectionColor = const Color(0x443399FF),
    this.onCustomEvent,
    this.variables = const {},
    this.toolbarBreakpoint = 768.0,
    this.onColorPickerRequested,
  });

  /// The controller that owns the document and selection state.
  final BlockController controller;

  /// An optional scroll controller for the block list.
  final ScrollController? scrollController;

  /// When true the editor is in read-only viewer mode.
  final bool readOnly;

  /// Padding around the block list.
  final EdgeInsets padding;

  /// The color of the blinking cursor.
  final Color cursorColor;

  /// The color of selection highlights.
  final Color selectionColor;

  /// Called when a third-party block plugin emits a [CustomBlockEvent].
  final void Function(CustomBlockEvent)? onCustomEvent;

  /// The variable resolution map for inline [VariableOp] embeds.
  final Map<String, String> variables;

  /// The screen width threshold in logical pixels that determines the
  /// formatting toolbar display mode. Defaults to 768.
  final double toolbarBreakpoint;

  /// Optional callback invoked when the user taps a color button in the
  /// formatting toolbar.
  ///
  /// When null the built-in 12-swatch palette popover is shown. When
  /// non-null this callback is awaited and its returned [Color] is applied
  /// if non-null. See the class-level documentation for full usage details.
  final Future<Color?> Function(Color? currentColor)? onColorPickerRequested;

  @override
  State<BlockEditorWidget> createState() => _BlockEditorWidgetState();
}

class _BlockEditorWidgetState extends State<BlockEditorWidget>
    implements TextInputClient {
  late StreamSubscription<DocumentChange> _changesSub;
  late StreamSubscription<EditorSelection> _selectionSub;
  late FocusNode _focusNode;
  late EditorEditingOperations _ops;
  late KeyboardShortcutHandler _shortcuts;
  final GlobalKey _editorKey = GlobalKey();
  final Map<String, GlobalKey> _blockKeys = {};
  final OverlayPortalController _toolbarController = OverlayPortalController();
  final OverlayPortalController _slashMenuController =
      OverlayPortalController();
  final OverlayPortalController _actionMenuController =
      OverlayPortalController();
  ScrollController? _internalScrollController;
  TextInputConnection? _inputConnection;
  TextRange _composingRange = TextRange.empty;
  bool _toolbarVisible = false;
  bool _slashMenuVisible = false;
  String? _slashTriggerBlockId;
  int _slashTriggerOffset = 0;
  bool _actionMenuVisible = false;
  String? _actionMenuBlockId;
  Offset _actionMenuPosition = Offset.zero;

  ScrollController get _scrollController =>
      widget.scrollController ?? _internalScrollController!;

  @override
  void initState() {
    super.initState();
    _ops = EditorEditingOperations(widget.controller);
    _shortcuts = KeyboardShortcutHandler(
      controller: widget.controller,
      ops: _ops,
    );
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
    if (widget.scrollController == null) {
      _internalScrollController = ScrollController();
    }
    _changesSub = widget.controller.changes.listen((change) {
      if (!mounted) return;
      if (change.type != ChangeType.update) setState(() {});
      _syncIMEState();
    });
    _selectionSub = widget.controller.selectionStream.listen((sel) {
      if (!mounted) return;
      setState(() {});
      _syncIMEState();
      _updateToolbarVisibility(sel);
    });
    _updateToolbarVisibility(widget.controller.selection);
  }

  @override
  void didUpdateWidget(BlockEditorWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _ops = EditorEditingOperations(widget.controller);
      _shortcuts = KeyboardShortcutHandler(
        controller: widget.controller,
        ops: _ops,
      );
      _changesSub.cancel();
      _selectionSub.cancel();
      _changesSub = widget.controller.changes.listen((change) {
        if (!mounted) return;
        if (change.type != ChangeType.update) setState(() {});
        _syncIMEState();
      });
      _selectionSub = widget.controller.selectionStream.listen((sel) {
        if (!mounted) return;
        setState(() {});
        _syncIMEState();
        _updateToolbarVisibility(sel);
      });
    }
    if (oldWidget.scrollController != widget.scrollController) {
      if (widget.scrollController == null &&
          _internalScrollController == null) {
        _internalScrollController = ScrollController();
      } else if (widget.scrollController != null) {
        _internalScrollController?.dispose();
        _internalScrollController = null;
      }
    }
  }

  @override
  void dispose() {
    _changesSub.cancel();
    _selectionSub.cancel();
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _inputConnection?.close();
    _internalScrollController?.dispose();
    super.dispose();
  }

  void _updateToolbarVisibility(EditorSelection sel) {
    if (widget.readOnly) {
      if (_toolbarVisible) {
        _toolbarController.hide();
        setState(() => _toolbarVisible = false);
      }
      return;
    }
    final shouldShow = sel is ExpandedSelection;
    if (shouldShow && !_toolbarVisible) {
      _toolbarController.show();
      setState(() => _toolbarVisible = true);
    } else if (!shouldShow && _toolbarVisible) {
      _toolbarController.hide();
      setState(() => _toolbarVisible = false);
    }
  }

  void _showSlashMenu({required String blockId, required int triggerOffset}) {
    setState(() {
      _slashTriggerBlockId = blockId;
      _slashTriggerOffset = triggerOffset;
      _slashMenuVisible = true;
    });
    _slashMenuController.show();
  }

  void _hideSlashMenu() {
    if (!_slashMenuVisible) return;
    _slashMenuController.hide();
    setState(() {
      _slashMenuVisible = false;
      _slashTriggerBlockId = null;
      _slashTriggerOffset = 0;
    });
  }

  void _showActionMenu(String blockId, Offset globalPosition) {
    setState(() {
      _actionMenuBlockId = blockId;
      _actionMenuPosition = globalPosition;
      _actionMenuVisible = true;
    });
    _actionMenuController.show();
  }

  void _hideActionMenu() {
    if (!_actionMenuVisible) return;
    _actionMenuController.hide();
    setState(() {
      _actionMenuVisible = false;
      _actionMenuBlockId = null;
      _actionMenuPosition = Offset.zero;
    });
  }

  GlobalKey _keyForBlock(String blockId) =>
      _blockKeys.putIfAbsent(blockId, () => GlobalKey());

  GlobalKey? _anchorKeyForSelection() {
    final sel = widget.controller.selection;
    if (sel is! ExpandedSelection) return null;
    return _blockKeys[sel.anchor.blockId];
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      _openIMEConnection();
    } else {
      _closeIMEConnection();
    }
  }

  void _openIMEConnection() {
    if (widget.readOnly) return;
    final sel = widget.controller.selection;
    if (sel is! CollapsedSelection) return;
    _inputConnection?.close();
    _inputConnection = TextInput.attach(
      this,
      const TextInputConfiguration(
        inputType: TextInputType.multiline,
        inputAction: TextInputAction.newline,
      ),
    );
    _inputConnection!.show();
    _syncIMEState();
  }

  void _closeIMEConnection() {
    _inputConnection?.close();
    _inputConnection = null;
    if (mounted) setState(() => _composingRange = TextRange.empty);
  }

  void _syncIMEState() {
    final connection = _inputConnection;
    if (connection == null || !connection.attached) return;
    final sel = widget.controller.selection;
    if (sel is! CollapsedSelection) return;
    final node = widget.controller.document.findById(sel.point.blockId);
    if (node == null) return;
    final text = node.delta?.plainText ?? '';
    final offset = sel.point.offset.clamp(0, text.length);
    connection.setEditingState(
      TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: offset),
        composing: _composingRange,
      ),
    );
  }

  @override
  void updateEditingValue(TextEditingValue value) {
    if (widget.readOnly) return;
    final sel = widget.controller.selection;
    if (sel is! CollapsedSelection) return;
    final blockId = sel.point.blockId;
    final node = widget.controller.document.findById(blockId);
    if (node == null) return;
    final currentText = node.delta?.plainText ?? '';
    final newText = value.text;
    if (newText != currentText) {
      _applyTextChange(
        blockId,
        currentText,
        newText,
        value.selection.baseOffset,
      );
    }
    if (mounted) setState(() => _composingRange = value.composing);
  }

  void _applyTextChange(
    String blockId,
    String currentText,
    String newText,
    int newCursorOffset,
  ) {
    final node = widget.controller.document.findById(blockId);
    if (node == null) return;
    final delta = node.delta ?? TextDelta.empty();

    int prefixLen = 0;
    while (prefixLen < currentText.length &&
        prefixLen < newText.length &&
        currentText[prefixLen] == newText[prefixLen]) {
      prefixLen++;
    }
    int suffixLen = 0;
    while (suffixLen < currentText.length - prefixLen &&
        suffixLen < newText.length - prefixLen &&
        currentText[currentText.length - 1 - suffixLen] ==
            newText[newText.length - 1 - suffixLen]) {
      suffixLen++;
    }

    final deleteStart = prefixLen;
    final deleteEnd = currentText.length - suffixLen;
    final insertedText = newText.substring(
      prefixLen,
      newText.length - suffixLen,
    );

    List<DeltaOp> ops = List.of(delta.ops);
    if (deleteEnd > deleteStart) {
      ops = _deleteRangeFromOps(ops, deleteStart, deleteEnd);
    }
    if (insertedText.isNotEmpty) {
      ops = _insertIntoOps(ops, deleteStart, insertedText);
    }

    widget.controller.updateDelta(blockId, TextDelta(ops));
    widget.controller.collapseSelection(
      blockId,
      newCursorOffset.clamp(0, newText.length),
    );
  }

  List<DeltaOp> _insertIntoOps(List<DeltaOp> ops, int offset, String text) {
    final attrs = _attributesAtOffset(ops, offset);
    if (ops.isEmpty) return [TextOp(text, attributes: attrs)];
    final result = <DeltaOp>[];
    var cursor = 0;
    var inserted = false;
    for (final op in ops) {
      if (op is! TextOp) {
        if (!inserted && cursor == offset) {
          result.add(TextOp(text, attributes: attrs));
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
        result.add(TextOp(text, attributes: attrs));
        if (after.isNotEmpty) {
          result.add(TextOp(after, attributes: op.attributes));
        }
        inserted = true;
      } else {
        result.add(op);
      }
      cursor = opEnd;
    }
    if (!inserted) result.add(TextOp(text, attributes: attrs));
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

  @override
  void performAction(TextInputAction action) {
    if (action == TextInputAction.newline) _ops.insertNewline();
  }

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {}
  @override
  void insertContent(KeyboardInsertedContent content) {}
  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {}
  @override
  void showAutocorrectionPromptRect(int start, int end) {}
  @override
  void connectionClosed() {
    _inputConnection = null;
    if (mounted) setState(() => _composingRange = TextRange.empty);
  }

  @override
  void didChangeInputControl(TextInputControl? o, TextInputControl? n) {}
  @override
  void insertTextPlaceholder(Size size) {}
  @override
  void removeTextPlaceholder() {}
  @override
  void performSelector(String selectorName) {}
  @override
  void showToolbar() {}

  // POC patch: TextInputClient.onFocusReceived was added in Flutter 3.47;
  // the default returns false (same as the SDK default).
  @override
  bool onFocusReceived() => false;

  @override
  TextEditingValue get currentTextEditingValue {
    final sel = widget.controller.selection;
    if (sel is! CollapsedSelection) return TextEditingValue.empty;
    final node = widget.controller.document.findById(sel.point.blockId);
    if (node == null) return TextEditingValue.empty;
    final text = node.delta?.plainText ?? '';
    final offset = sel.point.offset.clamp(0, text.length);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: offset),
      composing: _composingRange,
    );
  }

  @override
  AutofillScope? get currentAutofillScope => null;

  void _handleEvent(BlockEvent event) {
    if (widget.readOnly) return;
    switch (event) {
      case TapEvent():
        final offset = event.offset < 0 ? 0 : event.offset;
        widget.controller.collapseSelection(event.blockId, offset);
        _focusNode.requestFocus();
      case CheckboxToggledEvent():
        widget.controller.updateAttributes(event.blockId, {
          'checked': event.checked,
        });
      case BlockReorderedEvent():
        widget.controller.move(event.blockId, event.newIndex);
      case CustomBlockEvent():
        widget.onCustomEvent?.call(event);
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (widget.readOnly) return KeyEventResult.ignored;
    final result = _shortcuts.handle(event, ModifierKeys.fromHardware());
    if (result == KeyEventResult.handled) _checkSlashTrigger(event);
    return result;
  }

  void _checkSlashTrigger(KeyEvent event) {
    if (event.character != '/') return;
    final sel = widget.controller.selection;
    if (sel is! CollapsedSelection) return;
    final blockId = sel.point.blockId;
    final offset = sel.point.offset;
    final node = widget.controller.document.findById(blockId);
    if (node == null) return;
    final text = node.delta?.plainText ?? '';
    final isAtStart = offset == 1;
    final isAfterSpace = offset >= 2 && text[offset - 2] == ' ';
    if (isAtStart || isAfterSpace) {
      _showSlashMenu(blockId: blockId, triggerOffset: offset);
    }
  }

  bool _isFullyCovered(String blockId) {
    final sel = widget.controller.selection;
    if (sel is! ExpandedSelection) return false;
    final covered = widget.controller.selectedBlockIds;
    if (covered.length < 3) return false;
    return covered.sublist(1, covered.length - 1).contains(blockId);
  }

  int _resolveNumber(List<BlockNode> blocks, int index) {
    var count = 1;
    for (var i = index - 1; i >= 0; i--) {
      if (blocks[i].type == BlockTypes.numberedList) {
        count++;
      } else {
        break;
      }
    }
    return count;
  }

  EditorSelection _selectionForBlock(String blockId) {
    if (widget.readOnly) return EditorSelection.none;
    final sel = widget.controller.selection;
    if (sel is! ExpandedSelection) return sel;
    final ids = widget.controller.document.flatten().map((b) => b.id).toList();
    final resolved = sel.resolveOrder(ids);
    return ExpandedSelection(anchor: resolved.start, focus: resolved.end);
  }

  String? _focusedBlockId() {
    final sel = widget.controller.selection;
    if (sel is CollapsedSelection) return sel.point.blockId;
    return null;
  }

  double _editorWidth() {
    final box = _editorKey.currentContext?.findRenderObject() as RenderBox?;
    return box?.size.width ?? widget.toolbarBreakpoint;
  }

  @override
  Widget build(BuildContext context) {
    final blocks = widget.controller.document.blocks;
    final focusedId = _focusedBlockId();

    final list = ListView.builder(
      controller: _scrollController,
      padding: widget.padding,
      itemCount: blocks.length,
      itemBuilder: (context, index) {
        final rawNode = blocks[index];
        final blockKey = _keyForBlock(rawNode.id);
        final selection = _selectionForBlock(rawNode.id);
        final number = rawNode.type == BlockTypes.numberedList
            ? _resolveNumber(blocks, index)
            : 1;
        final node = rawNode.type == BlockTypes.numberedList
            ? rawNode.copyWith(
                attributes: {...rawNode.attributes, 'number': number},
              )
            : rawNode;
        final covered = _isFullyCovered(rawNode.id);
        final composing = focusedId == rawNode.id
            ? _composingRange
            : TextRange.empty;

        return BlockDropTarget(
          key: ValueKey('drop_${rawNode.id}'),
          index: index,
          blockId: rawNode.id,
          onEvent: _handleEvent,
          totalBlocks: blocks.length,
          blockIdResolver: (dragIndex) =>
              dragIndex < blocks.length ? blocks[dragIndex].id : null,
          child: BlockDragHandle(
            key: ValueKey('handle_${rawNode.id}'),
            index: index,
            blockId: rawNode.id,
            onEvent: _handleEvent,
            readOnly: widget.readOnly,
            onActionMenuRequested: widget.readOnly ? null : _showActionMenu,
            feedbackWidget: BlockGhost(
              node: rawNode,
              width: MediaQuery.of(context).size.width,
            ),
            child: KeyedSubtree(
              key: blockKey,
              child: _BlockItemWidget(
                key: ValueKey(rawNode.id),
                initialNode: node,
                controller: widget.controller,
                selection: selection,
                covered: covered,
                cursorColor: widget.cursorColor,
                selectionColor: widget.selectionColor,
                onEvent: _handleEvent,
                composingRange: composing,
              ),
            ),
          ),
        );
      },
    );

    if (widget.readOnly) {
      return BlockEditorScope(
        variables: widget.variables,
        readOnly: true,
        child: list,
      );
    }

    return BlockEditorScope(
      variables: widget.variables,
      readOnly: false,
      child: OverlayPortal(
        controller: _toolbarController,
        overlayChildBuilder: (_) => FormattingToolbar(
          controller: widget.controller,
          ops: _ops,
          anchorKey: _anchorKeyForSelection(),
          editorKey: _editorKey,
          toolbarBreakpoint: widget.toolbarBreakpoint,
          availableWidth: _editorWidth(),
          onColorPickerRequested: widget.onColorPickerRequested,
        ),
        child: OverlayPortal(
          controller: _slashMenuController,
          overlayChildBuilder: (_) => SlashCommandMenu(
            controller: widget.controller,
            ops: _ops,
            anchorKey: _slashTriggerBlockId != null
                ? _blockKeys[_slashTriggerBlockId]
                : null,
            editorKey: _editorKey,
            editorFocusNode: _focusNode,
            triggerBlockId: _slashTriggerBlockId ?? '',
            triggerOffset: _slashTriggerOffset,
            onDismiss: _hideSlashMenu,
          ),
          child: OverlayPortal(
            controller: _actionMenuController,
            overlayChildBuilder: (_) => BlockActionMenu(
              controller: widget.controller,
              blockId: _actionMenuBlockId ?? '',
              globalPosition: _actionMenuPosition,
              onDismiss: _hideActionMenu,
            ),
            child: Focus(
              key: _editorKey,
              focusNode: _focusNode,
              onKeyEvent: _handleKeyEvent,
              child: list,
            ),
          ),
        ),
      ),
    );
  }
}

class _BlockItemWidget extends StatefulWidget {
  const _BlockItemWidget({
    super.key,
    required this.initialNode,
    required this.controller,
    required this.selection,
    required this.covered,
    required this.cursorColor,
    required this.selectionColor,
    required this.onEvent,
    required this.composingRange,
  });

  final BlockNode initialNode;
  final BlockController controller;
  final EditorSelection selection;
  final bool covered;
  final Color cursorColor;
  final Color selectionColor;
  final void Function(BlockEvent) onEvent;
  final TextRange composingRange;

  @override
  State<_BlockItemWidget> createState() => _BlockItemWidgetState();
}

class _BlockItemWidgetState extends State<_BlockItemWidget> {
  late BlockNode _node;
  StreamSubscription<BlockNode>? _blockSub;

  BlockNode _applyTransientAttributes(BlockNode updated) {
    final transient = widget.initialNode.attributes;
    if (transient.isEmpty) return updated;
    return updated.copyWith(attributes: {...updated.attributes, ...transient});
  }

  @override
  void initState() {
    super.initState();
    _node = widget.initialNode;
    _blockSub = widget.controller.streamForBlock(widget.initialNode.id).listen((
      updated,
    ) {
      if (mounted) setState(() => _node = _applyTransientAttributes(updated));
    });
  }

  @override
  void didUpdateWidget(_BlockItemWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialNode.id != widget.initialNode.id ||
        oldWidget.controller != widget.controller) {
      _blockSub?.cancel();
      _node = widget.initialNode;
      _blockSub = widget.controller
          .streamForBlock(widget.initialNode.id)
          .listen((updated) {
            if (mounted) {
              setState(() => _node = _applyTransientAttributes(updated));
            }
          });
    } else {
      _node = widget.initialNode;
    }
  }

  @override
  void dispose() {
    _blockSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlockSelectionOverlay(
      isCovered: widget.covered,
      highlightColor: widget.selectionColor,
      child: BlockCursor(
        blockId: _node.id,
        delta: _node.delta ?? TextDelta.empty(),
        selection: widget.selection,
        cursorColor: widget.cursorColor,
        child: BlockRenderer(
          node: _node,
          onEvent: widget.onEvent,
          selection: widget.selection,
        ),
      ),
    );
  }
}
