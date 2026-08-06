import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:follow_the_leader/follow_the_leader.dart';
import 'package:super_editor/super_editor.dart';

import 'package:supanotes/features/notes/editor/document/note_editor_commands.dart';

import 'note_editor_interaction.dart';
import 'note_toolbar_button.dart';
import 'selection_formatting.dart';

class DesktopSelectionFormattingOverlay extends StatefulWidget {
  const DesktopSelectionFormattingOverlay({
    super.key,
    required this.enabled,
    required this.editor,
    required this.composer,
    required this.editorFocusNode,
    required this.selectionLayerLinks,
    required this.viewportKey,
    required this.child,
  });

  final bool enabled;
  final Editor editor;
  final MutableDocumentComposer composer;
  final FocusNode editorFocusNode;
  final SelectionLayerLinks selectionLayerLinks;
  final GlobalKey viewportKey;
  final Widget child;

  @override
  State<DesktopSelectionFormattingOverlay> createState() =>
      _DesktopSelectionFormattingOverlayState();
}

class _DesktopSelectionFormattingOverlayState
    extends State<DesktopSelectionFormattingOverlay> {
  late final OverlayPortalController _popoverController;
  late final FocusNode _popoverFocusNode;
  late final FollowerAligner _toolbarAligner;
  late FollowerBoundary _viewportBoundary;
  DocumentSelection? _selection;

  @override
  void initState() {
    super.initState();
    _popoverController = OverlayPortalController();
    _popoverFocusNode = FocusNode(debugLabel: 'desktop-formatting-popover');
    _toolbarAligner = PreferredPositionAligner.top(gap: 8);
    _selection = _expandedTextSelection(widget.composer.selection);
    widget.composer.selectionNotifier.addListener(_onSelectionChanged);
    widget.editor.context.document.addListener(_onDocumentChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _viewportBoundary = WidgetFollowerBoundary(boundaryKey: widget.viewportKey);
    _syncPopoverVisibility();
  }

  @override
  void didUpdateWidget(DesktopSelectionFormattingOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.composer != widget.composer ||
        oldWidget.editor != widget.editor) {
      oldWidget.composer.selectionNotifier.removeListener(_onSelectionChanged);
      oldWidget.editor.context.document.removeListener(_onDocumentChanged);
      widget.composer.selectionNotifier.addListener(_onSelectionChanged);
      widget.editor.context.document.addListener(_onDocumentChanged);
    }
    if (oldWidget.composer != widget.composer ||
        oldWidget.editor != widget.editor ||
        oldWidget.enabled != widget.enabled) {
      _selection = _expandedTextSelection(widget.composer.selection);
      _syncPopoverVisibility();
    }
  }

  @override
  void dispose() {
    widget.composer.selectionNotifier.removeListener(_onSelectionChanged);
    widget.editor.context.document.removeListener(_onDocumentChanged);
    _popoverFocusNode.dispose();
    super.dispose();
  }

  void _onSelectionChanged() {
    if (!mounted) return;
    setState(() {
      _selection = _expandedTextSelection(widget.composer.selection);
    });
    _syncPopoverVisibility();
  }

  void _onDocumentChanged(DocumentChangeLog changeLog) {
    if (!mounted) return;
    setState(() {
      _selection = _expandedTextSelection(widget.composer.selection);
    });
    _syncPopoverVisibility();
  }

  void _syncPopoverVisibility() {
    final shouldShow = widget.enabled && _selection != null;
    if (shouldShow) {
      _popoverController.show();
    } else if (_popoverController.isShowing) {
      _popoverController.hide();
    }
  }

  DocumentSelection? _expandedTextSelection(DocumentSelection? selection) {
    if (!widget.enabled || selection == null || selection.isCollapsed) {
      return null;
    }
    final nodes = editorSelectionNodes(
      widget.editor.context.document,
      selection,
    );
    return nodes.any((node) => node is TextNode) ? selection : null;
  }

  void _hidePopover() {
    if (_popoverController.isShowing) {
      _popoverController.hide();
    }
  }

  bool _prepareEditorAction() {
    final selection = _selection;
    if (selection == null ||
        !isEditorSelectionValid(widget.editor.context.document, selection)) {
      return false;
    }
    widget.editorFocusNode.requestFocus();
    if (widget.composer.selection != selection) {
      widget.composer.setSelectionWithReason(selection);
    }
    return true;
  }

  void _toggleAttribution(Attribution attribution) {
    if (!_prepareEditorAction()) return;
    HapticFeedback.selectionClick();
    NoteEditorCommands.toggleInlineAttribution(
      widget.editor,
      widget.composer,
      attribution,
    );
  }

  void _convertToListItem(ListItemType type) {
    if (!_prepareEditorAction()) return;
    HapticFeedback.selectionClick();
    NoteEditorCommands.convertToListItem(widget.editor, widget.composer, type);
  }

  void _convertToTask() {
    if (!_prepareEditorAction()) return;
    HapticFeedback.selectionClick();
    NoteEditorCommands.convertToTask(widget.editor, widget.composer);
  }

  @override
  Widget build(BuildContext context) {
    final document = widget.editor.context.document;
    final selectedNodes = NoteEditorCommands.selectedNodes(
      document,
      _selection,
    );
    final isBulleted =
        selectedNodes.isNotEmpty &&
        selectedNodes.every(
          (node) => node is ListItemNode && node.type == ListItemType.unordered,
        );
    final isNumbered =
        selectedNodes.isNotEmpty &&
        selectedNodes.every(
          (node) => node is ListItemNode && node.type == ListItemType.ordered,
        );
    final isTask =
        selectedNodes.isNotEmpty &&
        selectedNodes.every((node) => node is TaskNode);
    return OverlayPortal(
      controller: _popoverController,
      overlayChildBuilder: (context) => TapRegion(
        groupId: noteEditorToolbarTapRegionGroup,
        onTapOutside: (_) => _hidePopover(),
        child: FollowerFadeOutBeyondBoundary(
          link: widget.selectionLayerLinks.expandedSelectionBoundsLink,
          boundary: _viewportBoundary,
          child: Follower.withAligner(
            link: widget.selectionLayerLinks.expandedSelectionBoundsLink,
            aligner: _toolbarAligner,
            boundary: _viewportBoundary,
            showWhenUnlinked: false,
            child: SuperEditorPopover(
              popoverFocusNode: _popoverFocusNode,
              editorFocusNode: widget.editorFocusNode,
              child: _DesktopSelectionFormattingPopover(
                isBold: hasAttributionInEditorSelection(
                  document,
                  _selection,
                  boldAttribution,
                ),
                isItalic: hasAttributionInEditorSelection(
                  document,
                  _selection,
                  italicsAttribution,
                ),
                isStrikethrough: hasAttributionInEditorSelection(
                  document,
                  _selection,
                  strikethroughAttribution,
                ),
                isBulleted: isBulleted,
                isNumbered: isNumbered,
                isTask: isTask,
                onBold: () => _toggleAttribution(boldAttribution),
                onItalic: () => _toggleAttribution(italicsAttribution),
                onStrikethrough: () =>
                    _toggleAttribution(strikethroughAttribution),
                onBulleted: () => _convertToListItem(ListItemType.unordered),
                onNumbered: () => _convertToListItem(ListItemType.ordered),
                onTask: _convertToTask,
              ),
            ),
          ),
        ),
      ),
      child: KeyedSubtree(key: widget.viewportKey, child: widget.child),
    );
  }
}

class _DesktopSelectionFormattingPopover extends StatelessWidget {
  const _DesktopSelectionFormattingPopover({
    required this.isBold,
    required this.isItalic,
    required this.isStrikethrough,
    required this.isBulleted,
    required this.isNumbered,
    required this.isTask,
    required this.onBold,
    required this.onItalic,
    required this.onStrikethrough,
    required this.onBulleted,
    required this.onNumbered,
    required this.onTask,
  });

  final bool isBold;
  final bool isItalic;
  final bool isStrikethrough;
  final bool isBulleted;
  final bool isNumbered;
  final bool isTask;
  final VoidCallback onBold;
  final VoidCallback onItalic;
  final VoidCallback onStrikethrough;
  final VoidCallback onBulleted;
  final VoidCallback onNumbered;
  final VoidCallback onTask;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: 0.18),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        padding: const EdgeInsets.all(2),
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          label: 'Formatação da seleção',
          child: IntrinsicHeight(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ToolbarButton(
                  icon: Icons.format_bold,
                  spacious: false,
                  isActive: isBold,
                  onPressed: onBold,
                  semanticLabel: 'Negrito',
                ),
                ToolbarButton(
                  icon: Icons.format_italic,
                  spacious: false,
                  isActive: isItalic,
                  onPressed: onItalic,
                  semanticLabel: 'Itálico',
                ),
                ToolbarButton(
                  icon: Icons.format_strikethrough,
                  spacious: false,
                  isActive: isStrikethrough,
                  onPressed: onStrikethrough,
                  semanticLabel: 'Tachado',
                ),
                const ToolbarDivider(),
                ToolbarButton(
                  icon: Icons.format_list_bulleted,
                  spacious: false,
                  isActive: isBulleted,
                  onPressed: onBulleted,
                  semanticLabel: 'Lista com marcadores',
                ),
                ToolbarButton(
                  icon: Icons.format_list_numbered,
                  spacious: false,
                  isActive: isNumbered,
                  onPressed: onNumbered,
                  semanticLabel: 'Lista numerada',
                ),
                ToolbarButton(
                  svgAsset: 'assets/icons/checkbox.svg',
                  spacious: false,
                  isActive: isTask,
                  onPressed: onTask,
                  semanticLabel: 'Checklist',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
