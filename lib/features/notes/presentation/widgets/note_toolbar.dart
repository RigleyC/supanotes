library;

/// Compact horizontal toolbar for the note editor.
///
/// Each button mutates the editor by dispatching a single
/// `EditRequest` — the toolbar never reads or writes the document
/// directly. The active state (bold/italic/highlights) is reflected
/// back by re-reading the composer's selection on every rebuild and
/// checking what attributions are present at the caret / selection.
///
/// The toolbar rebuilds itself independently by listening to
/// [MutableDocumentComposer.selectionNotifier], so the parent widget
/// does not need to call `setState` whenever the selection changes.
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:super_editor/super_editor.dart';

import 'package:supanotes/features/notes/domain/note_editor_commands.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';

class NoteToolbar extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<DocumentSelection?>(
      valueListenable: composer.selectionNotifier,
      builder: (context, selection, child) {
        final activeNodeId = _activeNodeId(selection);
        final blockType = _activeBlockType(activeNodeId);
        final selectedListType = _selectedListType(selection);
        final isListItem = selectedListType != null;
        final activeNode = activeNodeId != null
            ? editor.context.document.getNodeById(activeNodeId)
            : null;
        final isTask = activeNode is TaskNode;
        final hasSelection = selection != null && !selection.isCollapsed;

        final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
        final bottomPadding = bottomInset > 0 ? 6.0 : 16.0;

        return Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPadding),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
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
                  vertical: 6,
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ClipRect(
                        child: AnimatedSize(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          alignment: Alignment.centerLeft,
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 180),
                            opacity: hasSelection ? 1.0 : 0.0,
                            curve: Curves.easeInOut,
                            child: hasSelection
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _ToolbarButton(
                                        icon: Icons.format_bold,
                                        isActive: _selectionHasAttribution(
                                          selection,
                                          boldAttribution,
                                        ),
                                        onPressed: () =>
                                            _toggleInline(boldAttribution),
                                      ),
                                      _ToolbarButton(
                                        icon: Icons.format_italic,
                                        isActive: _selectionHasAttribution(
                                          selection,
                                          italicsAttribution,
                                        ),
                                        onPressed: () =>
                                            _toggleInline(italicsAttribution),
                                      ),
                                      _ToolbarButton(
                                        icon: Icons.format_strikethrough,
                                        isActive: _selectionHasAttribution(
                                          selection,
                                          strikethroughAttribution,
                                        ),
                                        onPressed: () => _toggleInline(
                                          strikethroughAttribution,
                                        ),
                                      ),
                                      const _ToolbarDivider(),
                                    ],
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ),
                      ),
                      _ToolbarButton(
                        svgAsset: 'assets/icons/h1_icon.svg',
                        isActive: blockType == header1Attribution,
                        onPressed: () => _setBlockType(header1Attribution),
                      ),
                      _ToolbarButton(
                        svgAsset: 'assets/icons/h2_icon.svg',
                        isActive: blockType == header2Attribution,
                        onPressed: () => _setBlockType(header2Attribution),
                      ),
                      _ToolbarButton(
                        svgAsset: 'assets/icons/h3_icon.svg',
                        isActive: blockType == header3Attribution,
                        onPressed: () => _setBlockType(header3Attribution),
                      ),
                      _ToolbarButton(
                        icon: Icons.format_quote,
                        isActive: blockType == blockquoteAttribution,
                        onPressed: () => _setBlockType(blockquoteAttribution),
                      ),
                      const _ToolbarDivider(),
                      _ToolbarButton(
                        icon: Icons.check_box_outlined,
                        isActive: isTask,
                        onPressed: _convertToTask,
                      ),
                      _ToolbarButton(
                        icon: Icons.format_list_bulleted,
                        isActive: selectedListType == ListItemType.unordered,
                        onPressed: () =>
                            _convertToListItem(ListItemType.unordered),
                      ),
                      _ToolbarButton(
                        icon: Icons.format_list_numbered,
                        isActive: selectedListType == ListItemType.ordered,
                        onPressed: () =>
                            _convertToListItem(ListItemType.ordered),
                      ),
                      ClipRect(
                        child: AnimatedSize(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          alignment: Alignment.centerLeft,
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 180),
                            opacity: isListItem ? 1.0 : 0.0,
                            curve: Curves.easeInOut,
                            child: isListItem
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _ToolbarButton(
                                        icon: Icons.format_indent_increase,
                                        isActive: false,
                                        onPressed: _indentListItem,
                                      ),
                                      _ToolbarButton(
                                        icon: Icons.format_indent_decrease,
                                        isActive: false,
                                        onPressed: _unindentListItem,
                                      ),
                                    ],
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ),
                      ),
                      const _ToolbarDivider(),
                      _ToolbarButton(
                        icon: Icons.horizontal_rule,
                        isActive: false,
                        onPressed: _insertDivider,
                      ),
                      const _ToolbarDivider(),
                      _ToolbarButton(
                        icon: Icons.image,
                        isActive: false,
                        onPressed: onAttachImage,
                      ),
                      _ToolbarButton(
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
        );
      },
    );
  }

  String? _activeNodeId(DocumentSelection? selection) {
    if (selection == null) return null;
    if (selection.isCollapsed) return selection.extent.nodeId;
    return selection.start.nodeId;
  }

  Attribution? _activeBlockType(String? nodeId) {
    if (nodeId == null) return null;
    final node = editor.context.document.getNodeById(nodeId);
    if (node is ParagraphNode) {
      return node.getMetadataValue('blockType') as Attribution?;
    }
    if (node is ListItemNode) {
      return listItemAttribution;
    }
    return null;
  }

  ListItemType? _selectedListType(DocumentSelection? selection) {
    if (selection == null) return null;
    try {
      for (final node in NoteEditorCommands.selectedNodes(
        editor.context.document,
        selection,
      )) {
        if (node is ListItemNode) return node.type;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  bool _selectionHasAttribution(
    DocumentSelection? sel,
    Attribution attribution,
  ) {
    if (sel == null || sel.isCollapsed) return false;
    try {
      final nodes = editor.context.document
          .getNodesInside(sel.start, sel.end)
          .whereType<TextNode>();
      for (final node in nodes) {
        final start = (sel.start.nodeId == node.id)
            ? (sel.start.nodePosition as TextNodePosition).offset
            : 0;
        final end = (sel.end.nodeId == node.id)
            ? (sel.end.nodePosition as TextNodePosition).offset
            : node.text.length;
        if (start >= end) continue;
        if (node.text
            .getAttributionSpansInRange(
              attributionFilter: (a) => a == attribution,
              range: SpanRange(start, end),
            )
            .isNotEmpty) {
          return true;
        }
      }
    } catch (_) {
      return false;
    }
    return false;
  }

  void _toggleInline(Attribution attribution) {
    NoteEditorCommands.toggleInlineAttribution(editor, composer, attribution);
  }

  void _setBlockType(Attribution? attribution) {
    NoteEditorCommands.setBlockType(editor, composer, attribution);
  }

  void _convertToListItem(ListItemType type) {
    NoteEditorCommands.convertToListItem(editor, composer, type);
  }

  void _convertToTask() {
    NoteEditorCommands.convertToTask(editor, composer);
  }

  void _indentListItem() =>
      NoteEditorCommands.indentListItems(editor, composer);

  void _unindentListItem() =>
      NoteEditorCommands.unindentListItems(editor, composer);

  void _insertDivider() =>
      NoteEditorCommands.insertDivider(editor, dividerCount: 35);
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    this.icon,
    this.svgAsset,
    required this.isActive,
    this.onPressed,
  }) : assert(
         icon != null || svgAsset != null,
         'Provide either an icon or an svgAsset.',
       );

  final IconData? icon;
  final String? svgAsset;
  final bool isActive;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final fg = isActive
        ? colorScheme.primary
        : (onPressed == null
              ? colorScheme.onSurface.withValues(alpha: 0.38)
              : colorScheme.onSurface);

    return InkWell(
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      onTap: onPressed,
      child: Container(
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(AppSpacing.xs),
        decoration: BoxDecoration(
          color: isActive
              ? colorScheme.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        ),
        child: icon != null
            ? Icon(icon, size: 26, color: fg)
            : SvgPicture.asset(
                svgAsset!,
                width: 24,
                height: 24,
                colorFilter: ColorFilter.mode(fg, BlendMode.srcIn),
              ),
      ),
    );
  }
}

class _ToolbarDivider extends StatelessWidget {
  const _ToolbarDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 24,
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }
}
