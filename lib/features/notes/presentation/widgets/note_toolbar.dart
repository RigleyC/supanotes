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
library;

import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/theme/app_typography.dart';

class NoteToolbar extends StatelessWidget {
  const NoteToolbar({
    super.key,
    required this.editor,
    required this.composer,
  });

  final Editor editor;
  final MutableDocumentComposer composer;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DocumentSelection?>(
      valueListenable: composer.selectionNotifier,
      builder: (context, selection, child) {
        final activeNodeId = _activeNodeId(selection);
        final blockType = _activeBlockType(activeNodeId);
        return _ToolbarContainer(
          isBold: _selectionHasAttribution(selection, boldAttribution),
          isItalic: _selectionHasAttribution(selection, italicsAttribution),
          blockType: blockType,
          onToggleBold: () => _toggleInline(boldAttribution),
          onToggleItalic: () => _toggleInline(italicsAttribution),
          onSetH1: () => _setBlockType(header1Attribution),
          onSetH2: () => _setBlockType(header2Attribution),
          onSetH3: () => _setBlockType(header3Attribution),
          onConvertToUnorderedList: () => _convertToListItem(ListItemType.unordered),
          onConvertToOrderedList: () => _convertToListItem(ListItemType.ordered),
          onConvertToTask: _convertToTask,
          onConvertToQuote: () => _setBlockType(blockquoteAttribution),
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

  bool _selectionHasAttribution(DocumentSelection? selection, Attribution attribution) {
    if (selection == null) return false;
    final nodes = editor.context.document
        .getNodesInside(selection.start, selection.end)
        .whereType<TextNode>();
    for (final node in nodes) {
      final start = (selection.start.nodeId == node.id)
          ? (selection.start.nodePosition as TextPosition).offset
          : 0;
      final end = (selection.end.nodeId == node.id)
          ? (selection.end.nodePosition as TextPosition).offset
          : node.text.length;
      if (start >= end) continue;
      if (node.text.getAttributionSpansInRange(
            attributionFilter: (a) => a == attribution,
            range: SpanRange(start, end),
          ).isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  void _toggleInline(Attribution attribution) {
    final selection = composer.selection;
    if (selection == null) return;
    final range = selection.isCollapsed
        ? DocumentRange(start: selection.extent, end: selection.extent)
        : selection;
    editor.execute([
      ToggleTextAttributionsRequest(
        documentRange: range,
        attributions: {attribution},
      ),
    ]);
  }

  void _setBlockType(Attribution? blockType) {
    final nodeId = _activeNodeId(composer.selection);
    if (nodeId == null) return;
    final node = editor.context.document.getNodeById(nodeId);
    if (node is! ParagraphNode) return;
    editor.execute([
      ChangeParagraphBlockTypeRequest(nodeId: nodeId, blockType: blockType),
    ]);
  }

  void _convertToListItem(ListItemType type) {
    final nodeId = _activeNodeId(composer.selection);
    if (nodeId == null) return;
    final node = editor.context.document.getNodeById(nodeId);
    if (node is ListItemNode) {
      editor.execute([ChangeListItemTypeRequest(nodeId: nodeId, newType: type)]);
      return;
    }
    if (node is! ParagraphNode) return;
    editor.execute([ConvertParagraphToListItemRequest(nodeId: nodeId, type: type)]);
  }

  void _convertToTask() {
    final nodeId = _activeNodeId(composer.selection);
    if (nodeId == null) return;
    final node = editor.context.document.getNodeById(nodeId);
    if (node is! ParagraphNode) return;
    editor.execute([ConvertParagraphToTaskRequest(nodeId: nodeId)]);
  }
}

/// Pure presentational widget — receives only the resolved state and
/// callbacks. Decoupling it from the [NoteToolbar] shell allows it to
/// be rebuilt in isolation by [ValueListenableBuilder].
class _ToolbarContainer extends StatelessWidget {
  const _ToolbarContainer({
    required this.isBold,
    required this.isItalic,
    required this.blockType,
    required this.onToggleBold,
    required this.onToggleItalic,
    required this.onSetH1,
    required this.onSetH2,
    required this.onSetH3,
    required this.onConvertToUnorderedList,
    required this.onConvertToOrderedList,
    required this.onConvertToTask,
    required this.onConvertToQuote,
  });

  final bool isBold;
  final bool isItalic;
  final Attribution? blockType;
  final VoidCallback onToggleBold;
  final VoidCallback onToggleItalic;
  final VoidCallback onSetH1;
  final VoidCallback onSetH2;
  final VoidCallback onSetH3;
  final VoidCallback onConvertToUnorderedList;
  final VoidCallback onConvertToOrderedList;
  final VoidCallback onConvertToTask;
  final VoidCallback onConvertToQuote;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 4,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ToolbarButton(
              icon: Icons.format_bold,
              tooltip: 'Negrito',
              isActive: isBold,
              onPressed: onToggleBold,
            ),
            _ToolbarButton(
              icon: Icons.format_italic,
              tooltip: 'Itálico',
              isActive: isItalic,
              onPressed: onToggleItalic,
            ),
            const _ToolbarDivider(),
            _LabeledToolbarButton(
              label: 'H1',
              isActive: blockType == header1Attribution,
              onPressed: onSetH1,
            ),
            _LabeledToolbarButton(
              label: 'H2',
              isActive: blockType == header2Attribution,
              onPressed: onSetH2,
            ),
            _LabeledToolbarButton(
              label: 'H3',
              isActive: blockType == header3Attribution,
              onPressed: onSetH3,
            ),
            const _ToolbarDivider(),
            _ToolbarButton(
              icon: Icons.format_list_bulleted,
              tooltip: 'Lista',
              isActive: blockType == listItemAttribution,
              onPressed: onConvertToUnorderedList,
            ),
            _ToolbarButton(
              icon: Icons.format_list_numbered,
              tooltip: 'Lista numerada',
              isActive: false,
              onPressed: onConvertToOrderedList,
            ),
            _ToolbarButton(
              icon: Icons.check_box_outlined,
              tooltip: 'Tarefa',
              isActive: false,
              onPressed: onConvertToTask,
            ),
            _ToolbarButton(
              icon: Icons.format_quote,
              tooltip: 'Citação',
              isActive: blockType == blockquoteAttribution,
              onPressed: onConvertToQuote,
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.tooltip,
    required this.isActive,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final bool isActive;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon),
        iconSize: 20,
        visualDensity: VisualDensity.compact,
        isSelected: isActive,
        color: colorScheme.onSurface,
        selectedIcon: Icon(icon, color: colorScheme.primary),
        onPressed: onPressed,
      ),
    );
  }
}

class _LabeledToolbarButton extends StatelessWidget {
  const _LabeledToolbarButton({
    required this.label,
    required this.isActive,
    required this.onPressed,
  });

  final String label;
  final bool isActive;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final fg = isActive ? colorScheme.primary : colorScheme.onSurface;
    return Tooltip(
      message: 'Cabeçalho $label',
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        onTap: onPressed,
        child: Container(
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: isActive
                ? colorScheme.primary.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          ),
          child: Text(
            label,
            style: AppTypography.textTheme.labelLarge?.copyWith(
              color: fg,
              fontWeight: AppTypography.semibold,
            ),
          ),
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
