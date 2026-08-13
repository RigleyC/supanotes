library;

/// Compact horizontal toolbar for the note editor.
///
/// The toolbar delegates document mutations to [NoteEditorCommands]. It only
/// projects the current composer selection into button state and owns the
/// compact and formatting presentations.
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:super_editor/super_editor.dart';
import 'package:supanotes/core/utils/app_haptics.dart';

import 'package:supanotes/features/notes/editor/document/note_editor_commands.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';

import 'note_editor_interaction.dart';
import 'note_toolbar_button.dart';
import 'selection_formatting.dart';
export 'note_editor_interaction.dart' show noteEditorToolbarTapRegionGroup;
part 'note_toolbar_menus.dart';

class NoteToolbar extends StatefulWidget {
  const NoteToolbar({
    super.key,
    required this.editor,
    required this.composer,
    this.focusNode,
    this.softwareKeyboardController,
    this.onFormattingModeChanged,
    this.onAttachFile,
    this.onAttachImage,
  });

  final Editor editor;
  final MutableDocumentComposer composer;
  final FocusNode? focusNode;
  final SoftwareKeyboardController? softwareKeyboardController;
  final ValueChanged<bool>? onFormattingModeChanged;
  final VoidCallback? onAttachFile;
  final VoidCallback? onAttachImage;

  @override
  State<NoteToolbar> createState() => _NoteToolbarState();
}

enum _ToolbarMode { compact, formatting }

class _NoteToolbarState extends State<NoteToolbar> {
  Editor get editor => widget.editor;
  MutableDocumentComposer get composer => widget.composer;
  VoidCallback? get onAttachFile => widget.onAttachFile;
  VoidCallback? get onAttachImage => widget.onAttachImage;
  FocusNode? get focusNode => widget.focusNode;
  SoftwareKeyboardController? get softwareKeyboardController =>
      widget.softwareKeyboardController;
  ValueChanged<bool>? get onFormattingModeChanged =>
      widget.onFormattingModeChanged;

  _ToolbarMode _mode = _ToolbarMode.compact;
  DocumentSelection? _selectionForFormatting;
  FocusNode? _focusBeforeFormatting;
  bool _keyboardWasOpenBeforeFormatting = false;

  @override
  void initState() {
    super.initState();
    _attachListeners(widget);
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void didUpdateWidget(NoteToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.editor != widget.editor ||
        oldWidget.composer != widget.composer) {
      _detachListeners(oldWidget);
      _attachListeners(widget);
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _detachListeners(widget);
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (_mode == _ToolbarMode.formatting &&
        event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _closeFormatting();
      return true;
    }
    return false;
  }

  void _openFormatting() {
    if (_mode == _ToolbarMode.formatting) return;
    _focusBeforeFormatting = FocusManager.instance.primaryFocus;
    _selectionForFormatting = composer.selection;
    _keyboardWasOpenBeforeFormatting =
        MediaQuery.viewInsetsOf(context).bottom > 0;
    setState(() => _mode = _ToolbarMode.formatting);
    onFormattingModeChanged?.call(true);
    if (_keyboardWasOpenBeforeFormatting) {
      softwareKeyboardController?.hide();
    }
  }

  void _closeFormatting() {
    if (_mode == _ToolbarMode.compact) return;
    final focusToRestore = _focusBeforeFormatting ?? focusNode;
    final shouldRestoreKeyboard = _keyboardWasOpenBeforeFormatting;
    setState(() {
      _mode = _ToolbarMode.compact;
      _selectionForFormatting = null;
    });
    onFormattingModeChanged?.call(false);
    if (shouldRestoreKeyboard) {
      focusToRestore?.unfocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        focusToRestore?.requestFocus();
        softwareKeyboardController?.open(viewId: View.of(context).viewId);
      });
    }
    _focusBeforeFormatting = null;
    _keyboardWasOpenBeforeFormatting = false;
  }

  void _attachListeners(NoteToolbar toolbar) {
    toolbar.composer.selectionNotifier.addListener(_onEditorStateChanged);
    toolbar.editor.context.document.addListener(_onDocumentChanged);
  }

  void _detachListeners(NoteToolbar toolbar) {
    toolbar.composer.selectionNotifier.removeListener(_onEditorStateChanged);
    toolbar.editor.context.document.removeListener(_onDocumentChanged);
  }

  void _onEditorStateChanged() {
    if (mounted) setState(() {});
  }

  void _onDocumentChanged(DocumentChangeLog changeLog) =>
      _onEditorStateChanged();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final selection = composer.selection;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final bottomPadding = bottomInset > 0 ? 6.0 : 16.0;
    final formattingSelection = selection ?? _selectionForFormatting;
    final formattingNodes = _selectedNodes(formattingSelection);
    final formattingBlockType = _selectedBlockType(formattingNodes);
    final modeAnimationDuration = MediaQuery.of(context).disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 240);

    return PopScope(
      canPop: _mode == _ToolbarMode.compact,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _closeFormatting();
      },
      child: TapRegion(
        groupId: noteEditorToolbarTapRegionGroup,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPadding),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(
              _mode == _ToolbarMode.formatting ? 28 : 30,
            ),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                decoration: BoxDecoration(
                  color: colorScheme.surface.withValues(alpha: 0.78),
                  borderRadius: BorderRadius.circular(
                    _mode == _ToolbarMode.formatting ? 28 : 30,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.shadow.withValues(alpha: 0.1),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                  ),
                ),
                padding: _mode == _ToolbarMode.formatting
                    ? const EdgeInsets.fromLTRB(12, 12, 12, 10)
                    : const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: 8,
                      ),
                child: AnimatedSize(
                  duration: modeAnimationDuration,
                  curve: Curves.easeOutCubic,
                  child: _mode == _ToolbarMode.formatting
                      ? _FormattingToolbarPanel(
                          blockType: formattingBlockType,
                          selection: formattingSelection,
                          activeListOption: _activeListOption(formattingNodes),
                          isIndentableBlock: formattingNodes.any(
                            (node) => node is ListItemNode || node is TaskNode,
                          ),
                          isBold: _selectionHasAttribution(
                            formattingSelection,
                            boldAttribution,
                          ),
                          isItalic: _selectionHasAttribution(
                            formattingSelection,
                            italicsAttribution,
                          ),
                          isStrikethrough: _selectionHasAttribution(
                            formattingSelection,
                            strikethroughAttribution,
                          ),
                          onClose: _closeFormatting,
                          onBlockType: (attribution) => _onFormattingBlockType(
                            attribution,
                            formattingSelection,
                          ),
                          onToggleInline: (attribution) => _onFormattingInline(
                            attribution,
                            formattingSelection,
                          ),
                          onListSelected: (option) => _onListFormatSelected(
                            option,
                            formattingSelection,
                          ),
                          onIndent: () =>
                              _indentSelectedBlocks(formattingSelection),
                          onUnindent: () =>
                              _unindentSelectedBlocks(formattingSelection),
                        )
                      : SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ToolbarButton(
                                icon: Icons.text_format,
                                isActive: false,
                                onPressed: _openFormatting,
                                semanticLabel: 'Abrir formatação',
                              ),
                              const ToolbarDivider(),
                              ToolbarButton(
                                icon: Icons.horizontal_rule,
                                isActive: false,
                                onPressed: _insertDivider,
                              ),
                              const ToolbarDivider(),
                              ToolbarButton(
                                icon: Icons.image,
                                isActive: false,
                                onPressed: onAttachImage,
                              ),
                              ToolbarButton(
                                icon: Icons.attach_file,
                                isActive: false,
                                onPressed: onAttachFile,
                              ),
                            ],
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<DocumentNode> _selectedNodes(DocumentSelection? selection) {
    return editorSelectionNodes(editor.context.document, selection);
  }

  Attribution? _selectedBlockType(List<DocumentNode> nodes) {
    if (nodes.isEmpty || nodes.any((node) => node is! ParagraphNode)) {
      return null;
    }
    final blockTypes = nodes
        .cast<ParagraphNode>()
        .map((node) => node.getMetadataValue('blockType'))
        .whereType<Attribution>()
        .toSet();
    return blockTypes.length == 1 && blockTypes.length == nodes.length
        ? blockTypes.single
        : null;
  }

  ListItemType? _selectedListType(List<DocumentNode> nodes) {
    if (nodes.isEmpty || nodes.any((node) => node is! ListItemNode)) {
      return null;
    }
    final listTypes = nodes
        .cast<ListItemNode>()
        .map((node) => node.type)
        .toSet();
    return listTypes.length == 1 ? listTypes.single : null;
  }

  _ListFormatOption? _activeListOption(List<DocumentNode> nodes) {
    if (nodes.isNotEmpty && nodes.every((node) => node is TaskNode)) {
      return _ListFormatOption.checklist;
    }
    return switch (_selectedListType(nodes)) {
      ListItemType.unordered => _ListFormatOption.bulleted,
      ListItemType.ordered => _ListFormatOption.numbered,
      null => null,
    };
  }

  bool _selectionHasAttribution(
    DocumentSelection? selection,
    Attribution attribution,
  ) {
    return hasAttributionInEditorSelection(
      editor.context.document,
      selection,
      attribution,
    );
  }

  void _onFormattingBlockType(
    Attribution attribution,
    DocumentSelection? selection,
  ) {
    if (_prepareEditorAction(selection) == null) {
      _insertParagraphAtEnd(attribution);
      return;
    }
    AppHaptics.selectionChange();
    NoteEditorCommands.setBlockType(editor, composer, attribution);
  }

  void _onFormattingInline(
    Attribution attribution,
    DocumentSelection? selection,
  ) {
    if (selection == null || selection.isCollapsed) return;
    if (_prepareEditorAction(selection) == null) return;
    AppHaptics.selectionChange();
    NoteEditorCommands.toggleInlineAttribution(editor, composer, attribution);
  }

  DocumentSelection? _prepareEditorAction(DocumentSelection? selection) {
    if (selection == null || !_selectionIsValid(selection)) return null;
    focusNode?.requestFocus();
    if (composer.selection != selection) {
      composer.setSelectionWithReason(selection);
    }
    return selection;
  }

  bool _selectionIsValid(DocumentSelection selection) {
    return isEditorSelectionValid(editor.context.document, selection);
  }

  void _convertToListItem(ListItemType type) {
    AppHaptics.selectionChange();
    NoteEditorCommands.convertToListItem(editor, composer, type);
  }

  void _convertToTask() {
    AppHaptics.selectionChange();
    NoteEditorCommands.convertToTask(editor, composer);
  }

  void _onListFormatSelected(
    _ListFormatOption option,
    DocumentSelection? selection,
  ) {
    if (_prepareEditorAction(selection) == null) {
      _insertListBlockAtEnd(option);
      return;
    }
    switch (option) {
      case _ListFormatOption.bulleted:
        _convertToListItem(ListItemType.unordered);
      case _ListFormatOption.numbered:
        _convertToListItem(ListItemType.ordered);
      case _ListFormatOption.checklist:
        _convertToTask();
    }
  }

  void _indentSelectedBlocks(DocumentSelection? selection) {
    if (_prepareEditorAction(selection) == null) return;
    AppHaptics.selectionChange();
    NoteEditorCommands.indentSelectedBlocks(editor, composer);
  }

  void _unindentSelectedBlocks(DocumentSelection? selection) {
    if (_prepareEditorAction(selection) == null) return;
    AppHaptics.selectionChange();
    NoteEditorCommands.unindentSelectedBlocks(editor, composer);
  }

  void _insertDivider() {
    if (_prepareEditorAction(composer.selection) == null) {
      _insertDividerAtEnd();
      return;
    }
    AppHaptics.selectionChange();
    NoteEditorCommands.insertDivider(editor, dividerCount: 35);
  }

  void _insertParagraphAtEnd(Attribution blockType) {
    focusNode?.requestFocus();
    NoteEditorCommands.insertParagraphAtEnd(editor, blockType: blockType);
    AppHaptics.selectionChange();
  }

  void _insertListBlockAtEnd(_ListFormatOption option) {
    focusNode?.requestFocus();
    switch (option) {
      case _ListFormatOption.bulleted:
        NoteEditorCommands.insertListItemAtEnd(
          editor,
          type: ListItemType.unordered,
        );
      case _ListFormatOption.numbered:
        NoteEditorCommands.insertListItemAtEnd(
          editor,
          type: ListItemType.ordered,
        );
      case _ListFormatOption.checklist:
        NoteEditorCommands.insertTaskAtEnd(editor);
    }
    AppHaptics.selectionChange();
  }

  void _insertDividerAtEnd() {
    focusNode?.requestFocus();
    NoteEditorCommands.insertDividerAtEnd(editor, dividerCount: 35);
    AppHaptics.selectionChange();
  }
}
