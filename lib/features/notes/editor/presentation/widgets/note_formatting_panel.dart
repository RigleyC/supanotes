// Full formatting panel for the note editor.
//
// The parent owns panel transitions, keyboard visibility, and editor focus.
import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

import 'package:supanotes/features/notes/editor/document/note_editor_commands.dart';

import 'note_toolbar_button.dart';
import 'selection_formatting.dart';

part 'note_toolbar_menus.dart';

class NoteFormattingPanel extends StatefulWidget {
  const NoteFormattingPanel({
    super.key,
    required this.editor,
    required this.composer,
    required this.selection,
    required this.onClose,
    required this.onReturnToTyping,
  });

  final Editor editor;
  final MutableDocumentComposer composer;
  final DocumentSelection? selection;
  final VoidCallback onClose;
  final VoidCallback onReturnToTyping;

  @override
  State<NoteFormattingPanel> createState() => _NoteFormattingPanelState();
}

class _NoteFormattingPanelState extends State<NoteFormattingPanel> {
  @override
  void initState() {
    super.initState();
    widget.editor.context.document.addListener(_onDocumentChanged);
  }

  @override
  void didUpdateWidget(NoteFormattingPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.editor != widget.editor) {
      oldWidget.editor.context.document.removeListener(_onDocumentChanged);
      widget.editor.context.document.addListener(_onDocumentChanged);
    }
  }

  @override
  void dispose() {
    widget.editor.context.document.removeListener(_onDocumentChanged);
    super.dispose();
  }

  void _onDocumentChanged(DocumentChangeLog changeLog) {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final nodes = editorSelectionNodes(
      widget.editor.context.document,
      widget.selection,
    );

    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Painel de formatação',
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Formatar',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: 'Voltar a digitar',
                    child: ToolbarButton(
                      icon: Icons.keyboard,
                      spacious: true,
                      isActive: false,
                      haptic: ToolbarHaptic.controlTap,
                      onPressed: widget.onReturnToTyping,
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: 'Fechar formatação',
                    child: ToolbarButton(
                      icon: Icons.close,
                      spacious: true,
                      isActive: false,
                      haptic: ToolbarHaptic.controlTap,
                      onPressed: widget.onClose,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: _FormattingMenu(
                  blockType: _selectedBlockType(nodes),
                  hasSelection: !(widget.selection?.isCollapsed ?? true),
                  isBold: _selectionHasAttribution(boldAttribution),
                  isItalic: _selectionHasAttribution(italicsAttribution),
                  isStrikethrough: _selectionHasAttribution(
                    strikethroughAttribution,
                  ),
                  onBlockType: _onFormattingBlockType,
                  onToggleInline: _onFormattingInline,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ListFormatMenu(
                    activeOption: _activeListOption(nodes),
                    onSelected: _onListFormatSelected,
                  ),
                  if (nodes.any(
                    (node) => node is ListItemNode || node is TaskNode,
                  )) ...[
                    const ToolbarDivider(),
                    ToolbarButton(
                      icon: Icons.format_indent_increase,
                      isActive: false,
                      haptic: ToolbarHaptic.selectionChange,
                      onPressed: _indentSelectedBlocks,
                      semanticLabel: 'Aumentar recuo',
                    ),
                    ToolbarButton(
                      icon: Icons.format_indent_decrease,
                      isActive: false,
                      haptic: ToolbarHaptic.selectionChange,
                      onPressed: _unindentSelectedBlocks,
                      semanticLabel: 'Diminuir recuo',
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
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

  bool _selectionHasAttribution(Attribution attribution) {
    return hasAttributionInEditorSelection(
      widget.editor.context.document,
      widget.selection,
      attribution,
    );
  }

  void _onFormattingBlockType(Attribution attribution) {
    if (_prepareEditorAction() == null) {
      NoteEditorCommands.insertParagraphAtEnd(
        widget.editor,
        blockType: attribution,
      );
      return;
    }
    NoteEditorCommands.setBlockType(
      widget.editor,
      widget.composer,
      attribution,
    );
  }

  void _onFormattingInline(Attribution attribution) {
    final selection = widget.selection;
    if (selection == null || selection.isCollapsed) return;
    if (_prepareEditorAction() == null) return;
    NoteEditorCommands.toggleInlineAttribution(
      widget.editor,
      widget.composer,
      attribution,
    );
  }

  DocumentSelection? _prepareEditorAction() {
    final selection = widget.selection;
    if (selection == null || !_selectionIsValid(selection)) return null;
    if (widget.composer.selection != selection) {
      widget.composer.setSelectionWithReason(selection);
    }
    return selection;
  }

  bool _selectionIsValid(DocumentSelection selection) {
    return isEditorSelectionValid(widget.editor.context.document, selection);
  }

  void _onListFormatSelected(_ListFormatOption option) {
    if (_prepareEditorAction() == null) {
      _insertListBlockAtEnd(option);
      return;
    }
    switch (option) {
      case _ListFormatOption.bulleted:
        NoteEditorCommands.convertToListItem(
          widget.editor,
          widget.composer,
          ListItemType.unordered,
        );
      case _ListFormatOption.numbered:
        NoteEditorCommands.convertToListItem(
          widget.editor,
          widget.composer,
          ListItemType.ordered,
        );
      case _ListFormatOption.checklist:
        NoteEditorCommands.convertToTask(widget.editor, widget.composer);
    }
  }

  void _indentSelectedBlocks() {
    if (_prepareEditorAction() == null) return;
    NoteEditorCommands.indentSelectedBlocks(widget.editor, widget.composer);
  }

  void _unindentSelectedBlocks() {
    if (_prepareEditorAction() == null) return;
    NoteEditorCommands.unindentSelectedBlocks(widget.editor, widget.composer);
  }

  void _insertListBlockAtEnd(_ListFormatOption option) {
    switch (option) {
      case _ListFormatOption.bulleted:
        NoteEditorCommands.insertListItemAtEnd(
          widget.editor,
          type: ListItemType.unordered,
        );
      case _ListFormatOption.numbered:
        NoteEditorCommands.insertListItemAtEnd(
          widget.editor,
          type: ListItemType.ordered,
        );
      case _ListFormatOption.checklist:
        NoteEditorCommands.insertTaskAtEnd(widget.editor);
    }
  }
}
