// Compact contextual toolbar for the note editor.
//
// The toolbar derives its content from the editor selection and active nodes.
// A paragraph-level interaction shows block-format controls; selecting text or
// placing the caret in a list/task shows inline and block conversion controls.
// The toolbar shell keeps a single position and height - only its action
// content animates between the two modes.
import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:motor/motor.dart';
import 'package:super_editor/super_editor.dart';

import 'package:supanotes/features/notes/editor/document/note_editor_commands.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';

import 'note_editor_interaction.dart';
import 'note_toolbar_button.dart';
import 'selection_formatting.dart';

export 'note_editor_interaction.dart' show noteEditorToolbarTapRegionGroup;

enum _ToolbarMode { normal, contextual }

class NoteToolbar extends StatefulWidget {
  const NoteToolbar({
    super.key,
    required this.editor,
    required this.composer,
    this.onAttachFile,
    this.onAttachImage,
  });

  final Editor editor;
  final MutableDocumentComposer composer;
  final VoidCallback? onAttachFile;
  final VoidCallback? onAttachImage;

  @override
  State<NoteToolbar> createState() => _NoteToolbarState();
}

class _NoteToolbarState extends State<NoteToolbar> {
  List<DocumentNode> _selected = const [];

  @override
  void initState() {
    super.initState();
    widget.composer.selectionNotifier.addListener(_onStateChange);
    widget.editor.context.document.addListener(_onStateChange);
    _refreshSelected();
  }

  @override
  void didUpdateWidget(NoteToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.composer != widget.composer) {
      oldWidget.composer.selectionNotifier.removeListener(_onStateChange);
      widget.composer.selectionNotifier.addListener(_onStateChange);
    }
    if (oldWidget.editor != widget.editor) {
      oldWidget.editor.context.document.removeListener(_onStateChange);
      widget.editor.context.document.addListener(_onStateChange);
    }
    _onStateChange();
  }

  @override
  void dispose() {
    widget.composer.selectionNotifier.removeListener(_onStateChange);
    widget.editor.context.document.removeListener(_onStateChange);
    super.dispose();
  }

  void _onStateChange([DocumentChangeLog? _]) {
    if (!mounted) return;
    setState(_refreshSelected);
  }

  void _refreshSelected() {
    _selected = editorSelectionNodes(
      widget.editor.context.document,
      widget.composer.selection,
    );
  }

  bool get _isContextual {
    final selection = widget.composer.selection;
    if (selection == null) return false;
    if (!selection.isCollapsed) return true;
    final node = widget.editor.context.document.getNodeById(
      selection.extent.nodeId,
    );
    return node is ListItemNode || node is TaskNode;
  }

  bool get _hasTextSelection {
    final selection = widget.composer.selection;
    return selection != null && !selection.isCollapsed;
  }

  bool get _hasListOrTask => _selected.any(
        (node) => node is ListItemNode || node is TaskNode,
      );

  @override
  Widget build(BuildContext context) {
    return TapRegion(
      groupId: noteEditorToolbarTapRegionGroup,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: _ContextualToolbarContent(
              mode: _isContextual ? _ToolbarMode.contextual : _ToolbarMode.normal,
              normalRow: _buildNormalRow(),
              contextualRow: _buildContextualRow(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNormalRow() {
    final blockType = _selectedBlockType();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ToolbarButton(
          svgAsset: 'assets/icons/h1_icon.svg',
          spacious: true,
          isActive: blockType == header1Attribution,
          haptic: ToolbarHaptic.selectionChange,
          onPressed: () => _setBlockType(header1Attribution),
          semanticLabel: 'Título 1',
        ),
        ToolbarButton(
          svgAsset: 'assets/icons/h2_icon.svg',
          spacious: true,
          isActive: blockType == header2Attribution,
          haptic: ToolbarHaptic.selectionChange,
          onPressed: () => _setBlockType(header2Attribution),
          semanticLabel: 'Título 2',
        ),
        ToolbarButton(
          svgAsset: 'assets/icons/h3_icon.svg',
          spacious: true,
          isActive: blockType == header3Attribution,
          haptic: ToolbarHaptic.selectionChange,
          onPressed: () => _setBlockType(header3Attribution),
          semanticLabel: 'Título 3',
        ),
        ToolbarButton(
          icon: Icons.format_quote,
          spacious: true,
          isActive: blockType == blockquoteAttribution,
          haptic: ToolbarHaptic.selectionChange,
          onPressed: () => _setBlockType(blockquoteAttribution),
          semanticLabel: 'Citação',
        ),
        const ToolbarDivider(),
        ToolbarButton(
          icon: Icons.horizontal_rule,
          spacious: true,
          isActive: false,
          haptic: ToolbarHaptic.selectionChange,
          onPressed: _insertDivider,
          semanticLabel: 'Inserir divisor',
        ),
        const ToolbarDivider(),
        ToolbarButton(
          icon: Icons.image,
          spacious: true,
          isActive: false,
          haptic: ToolbarHaptic.controlTap,
          onPressed: widget.onAttachImage,
          semanticLabel: 'Inserir imagem',
        ),
        ToolbarButton(
          icon: Icons.attach_file,
          spacious: true,
          isActive: false,
          haptic: ToolbarHaptic.controlTap,
          onPressed: widget.onAttachFile,
          semanticLabel: 'Anexar arquivo',
        ),
      ],
    );
  }

  Widget _buildContextualRow() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ToolbarButton(
          icon: Icons.format_bold,
          spacious: true,
          isActive: _hasAttribution(boldAttribution),
          haptic: ToolbarHaptic.selectionChange,
          onPressed: _hasTextSelection
              ? () => _toggleInline(boldAttribution)
              : null,
          semanticLabel: 'Negrito',
        ),
        ToolbarButton(
          icon: Icons.format_italic,
          spacious: true,
          isActive: _hasAttribution(italicsAttribution),
          haptic: ToolbarHaptic.selectionChange,
          onPressed: _hasTextSelection
              ? () => _toggleInline(italicsAttribution)
              : null,
          semanticLabel: 'Itálico',
        ),
        ToolbarButton(
          icon: Icons.format_strikethrough,
          spacious: true,
          isActive: _hasAttribution(strikethroughAttribution),
          haptic: ToolbarHaptic.selectionChange,
          onPressed: _hasTextSelection
              ? () => _toggleInline(strikethroughAttribution)
              : null,
          semanticLabel: 'Tachado',
        ),
        const ToolbarDivider(),
        ToolbarButton(
          icon: Icons.format_list_bulleted,
          spacious: true,
          isActive: _selectedListType() == ListItemType.unordered,
          haptic: ToolbarHaptic.selectionChange,
          onPressed: () => _convertToList(ListItemType.unordered),
          semanticLabel: 'Lista com marcadores',
        ),
        ToolbarButton(
          icon: Icons.format_list_numbered,
          spacious: true,
          isActive: _selectedListType() == ListItemType.ordered,
          haptic: ToolbarHaptic.selectionChange,
          onPressed: () => _convertToList(ListItemType.ordered),
          semanticLabel: 'Lista numerada',
        ),
        ToolbarButton(
          svgAsset: 'assets/icons/checkbox.svg',
          spacious: true,
          isActive: _selected.every((node) => node is TaskNode),
          haptic: ToolbarHaptic.selectionChange,
          onPressed: _convertToTask,
          semanticLabel: 'Task',
        ),
        const ToolbarDivider(),
        ToolbarButton(
          icon: Icons.format_indent_decrease,
          spacious: true,
          isActive: false,
          haptic: ToolbarHaptic.selectionChange,
          onPressed: _hasListOrTask ? _unindentSelectedBlocks : null,
          semanticLabel: 'Diminuir recuo',
        ),
        ToolbarButton(
          icon: Icons.format_indent_increase,
          spacious: true,
          isActive: false,
          haptic: ToolbarHaptic.selectionChange,
          onPressed: _hasListOrTask ? _indentSelectedBlocks : null,
          semanticLabel: 'Aumentar recuo',
        ),
      ],
    );
  }

  Attribution? _selectedBlockType() {
    final nodes = _selected;
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

  ListItemType? _selectedListType() {
    final nodes = _selected;
    if (nodes.isEmpty || nodes.any((node) => node is! ListItemNode)) {
      return null;
    }
    final listTypes = nodes.cast<ListItemNode>().map((node) => node.type).toSet();
    return listTypes.length == 1 ? listTypes.single : null;
  }

  bool _hasAttribution(Attribution attribution) {
    return hasAttributionInEditorSelection(
      widget.editor.context.document,
      widget.composer.selection,
      attribution,
    );
  }

  void _setBlockType(Attribution attribution) {
    NoteEditorCommands.setBlockType(
      widget.editor,
      widget.composer,
      attribution,
    );
  }

  void _toggleInline(Attribution attribution) {
    NoteEditorCommands.toggleInlineAttribution(
      widget.editor,
      widget.composer,
      attribution,
    );
  }

  void _convertToList(ListItemType type) {
    NoteEditorCommands.convertToListItem(widget.editor, widget.composer, type);
  }

  void _convertToTask() {
    NoteEditorCommands.convertToTask(widget.editor, widget.composer);
  }

  void _indentSelectedBlocks() {
    NoteEditorCommands.indentSelectedBlocks(widget.editor, widget.composer);
  }

  void _unindentSelectedBlocks() {
    NoteEditorCommands.unindentSelectedBlocks(widget.editor, widget.composer);
  }

  void _insertDivider() {
    final selection = widget.composer.selection;
    if (selection == null ||
        !isEditorSelectionValid(widget.editor.context.document, selection)) {
      NoteEditorCommands.insertDividerAtEnd(widget.editor, dividerCount: 35);
      return;
    }
    NoteEditorCommands.insertDivider(widget.editor, dividerCount: 35);
  }
}

class _ContextualToolbarContent extends StatefulWidget {
  const _ContextualToolbarContent({
    required this.mode,
    required this.normalRow,
    required this.contextualRow,
  });

  final _ToolbarMode mode;
  final Widget normalRow;
  final Widget contextualRow;

  @override
  State<_ContextualToolbarContent> createState() =>
      _ContextualToolbarContentState();
}

class _ContextualToolbarContentState extends State<_ContextualToolbarContent>
    with TickerProviderStateMixin {
  late final SingleMotionController _motion;
  bool _animationsDisabled = false;

  @override
  void initState() {
    super.initState();
    _motion = SingleMotionController(
      motion: const MaterialSpringMotion.standardEffectsFast(),
      vsync: this,
      initialValue: 1,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final disabled = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (disabled != _animationsDisabled) {
      _animationsDisabled = disabled;
      _applyMotion();
    }
  }

  @override
  void didUpdateWidget(_ContextualToolbarContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode) {
      _applyMotion();
    }
  }

  void _applyMotion() {
    if (_animationsDisabled) {
      _motion.value = 1;
      return;
    }
    _motion.value = 0;
    unawaited(_motion.animateTo(1).orCancel.catchError((_) {}));
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final incoming = widget.mode == _ToolbarMode.normal
        ? widget.normalRow
        : widget.contextualRow;
    final outgoing = widget.mode == _ToolbarMode.normal
        ? widget.contextualRow
        : widget.normalRow;

    return Container(
      key: const ValueKey('note-toolbar-shell'),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(30),
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
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 8,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: AnimatedBuilder(
          animation: _motion,
          builder: (_, _) {
            final progress = _motion.value.clamp(0.0, 1.0);
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  child: ExcludeSemantics(
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: 1 - progress,
                        child: Transform.translate(
                          offset: Offset(-(1 - progress) * 8, 0),
                          child: Transform.scale(
                            scale: 0.96 + 0.04 * progress,
                            alignment: Alignment.centerLeft,
                            child: outgoing,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Opacity(
                  opacity: 0.35 + 0.65 * progress,
                  child: Transform.translate(
                    offset: Offset((1 - progress) * 8, 0),
                    child: Transform.scale(
                      scale: 0.96 + 0.04 * progress,
                      alignment: Alignment.centerLeft,
                      child: incoming,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}