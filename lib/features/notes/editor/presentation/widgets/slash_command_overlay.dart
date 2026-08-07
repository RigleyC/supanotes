import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:follow_the_leader/follow_the_leader.dart';
import 'package:super_editor/super_editor.dart';

import 'package:supanotes/features/notes/editor/document/note_editor_commands.dart';
import 'package:supanotes/features/notes/editor/document/slash_command_options.dart';

/// Keyboard action for navigation and dismissal while the slash menu is visible.
SuperEditorKeyboardAction slashMenuKeyboardHandler(
  SlashCommandController controller,
) {
  return ({
    required SuperEditorContext editContext,
    required KeyEvent keyEvent,
  }) {
    if (!controller.isVisible) {
      return ExecutionInstruction.continueExecution;
    }

    if (keyEvent is! KeyDownEvent && keyEvent is! KeyRepeatEvent) {
      return ExecutionInstruction.continueExecution;
    }

    if (keyEvent.logicalKey == LogicalKeyboardKey.arrowDown) {
      controller.moveDown();
      return ExecutionInstruction.haltExecution;
    }

    if (keyEvent.logicalKey == LogicalKeyboardKey.arrowUp) {
      controller.moveUp();
      return ExecutionInstruction.haltExecution;
    }

    if (keyEvent.logicalKey == LogicalKeyboardKey.enter) {
      controller.selectCurrent();
      return ExecutionInstruction.haltExecution;
    }

    if (keyEvent.logicalKey == LogicalKeyboardKey.escape) {
      controller.dismiss();
      return ExecutionInstruction.haltExecution;
    }

    if (keyEvent.logicalKey == LogicalKeyboardKey.tab) {
      controller.dismiss();
      return ExecutionInstruction.continueExecution;
    }

    return ExecutionInstruction.continueExecution;
  };
}

/// Controller for slash command menu state. Local per-overlay instance.
class SlashCommandController extends ChangeNotifier {
  bool _isVisible = false;
  int _selectedIndex = 0;
  List<SlashCommandOption> _filteredOptions = [];
  void Function(SlashCommandOption option)? _onSelectOption;
  VoidCallback? _onDismiss;

  bool get isVisible => _isVisible;
  int get selectedIndex => _selectedIndex;
  List<SlashCommandOption> get filteredOptions => _filteredOptions;

  void show({
    required List<SlashCommandOption> filteredOptions,
    required void Function(SlashCommandOption option) onSelectOption,
    required VoidCallback onDismiss,
  }) {
    _isVisible = true;
    _filteredOptions = filteredOptions;
    _selectedIndex = 0;
    _onSelectOption = onSelectOption;
    _onDismiss = onDismiss;
    notifyListeners();
  }

  void hide() {
    if (!_isVisible) return;
    _isVisible = false;
    _filteredOptions = [];
    _selectedIndex = 0;
    _onSelectOption = null;
    _onDismiss = null;
    notifyListeners();
  }

  void moveDown() {
    if (!_isVisible || _filteredOptions.isEmpty) return;
    _selectedIndex = (_selectedIndex + 1) % _filteredOptions.length;
    notifyListeners();
  }

  void moveUp() {
    if (!_isVisible || _filteredOptions.isEmpty) return;
    _selectedIndex =
        (_selectedIndex - 1 + _filteredOptions.length) %
        _filteredOptions.length;
    notifyListeners();
  }

  void selectCurrent() {
    if (!_isVisible || _filteredOptions.isEmpty) return;
    final option = _filteredOptions[_selectedIndex];
    _onSelectOption?.call(option);
  }

  void dismiss() {
    _onDismiss?.call();
    hide();
  }
}

class _SlashMatch {
  final String nodeId;
  final int slashOffset;
  final int caretOffset;

  const _SlashMatch({
    required this.nodeId,
    required this.slashOffset,
    required this.caretOffset,
  });
}

class SlashCommandOverlay extends StatefulWidget {
  final Editor editor;
  final DocumentComposer composer;
  final SelectionLayerLinks selectionLayerLinks;
  final GlobalKey viewportKey;
  final SlashCommandController controller;
  final FocusNode? focusNode;
  final VoidCallback? onAttachImage;
  final VoidCallback? onAttachFile;

  const SlashCommandOverlay({
    super.key,
    required this.editor,
    required this.composer,
    required this.selectionLayerLinks,
    required this.viewportKey,
    required this.controller,
    this.focusNode,
    this.onAttachImage,
    this.onAttachFile,
  });

  @override
  State<SlashCommandOverlay> createState() => _SlashCommandOverlayState();
}

class _SlashCommandOverlayState extends State<SlashCommandOverlay> {
  late final OverlayPortalController _menuPortalController;
  late final FocusNode _menuFocusNode;
  late final FollowerAligner _menuAligner;
  late FollowerBoundary _viewportBoundary;
  _SlashMatch? _match;

  @override
  void initState() {
    super.initState();
    _menuPortalController = OverlayPortalController();
    _menuFocusNode = FocusNode(debugLabel: 'slash-command-menu');
    _menuAligner = PreferredPositionAligner.bottom(gap: 8);
    widget.composer.selectionNotifier.addListener(_onSelectionChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _viewportBoundary = WidgetFollowerBoundary(boundaryKey: widget.viewportKey);
    _syncMenuVisibility();
  }

  @override
  void didUpdateWidget(SlashCommandOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.composer != oldWidget.composer) {
      oldWidget.composer.selectionNotifier.removeListener(_onSelectionChanged);
      widget.composer.selectionNotifier.addListener(_onSelectionChanged);
      _onSelectionChanged();
    }
  }

  @override
  void dispose() {
    widget.composer.selectionNotifier.removeListener(_onSelectionChanged);
    _menuFocusNode.dispose();
    super.dispose();
  }

  void _onSelectionChanged() {
    final selection = widget.composer.selection;
    if (selection == null || !selection.isCollapsed) {
      if (_match != null) _clearMatch();
      return;
    }

    final position = selection.extent;
    final nodeId = position.nodeId;
    final node = widget.editor.document.getNodeById(nodeId);
    if (node is! ParagraphNode) {
      if (_match != null) _clearMatch();
      return;
    }

    final text = node.text.toPlainText();
    final caretOffset = (position.nodePosition as TextNodePosition).offset;

    final textBeforeCaret = text.substring(0, caretOffset);
    final match = RegExp(
      r'^\s*\/([a-zA-Z0-9_-]*)$',
    ).firstMatch(textBeforeCaret);

    if (match == null) {
      if (_match != null) _clearMatch();
      return;
    }

    final slashOffset = textBeforeCaret.lastIndexOf('/');
    final query = match.group(1) ?? '';
    final filtered =
        defaultSlashCommandOptions.where((opt) => opt.matches(query)).toList()
          ..sort((left, right) {
            final score = right
                .matchScore(query)
                .compareTo(left.matchScore(query));
            if (score != 0) return score;
            return defaultSlashCommandOptions
                .indexOf(left)
                .compareTo(defaultSlashCommandOptions.indexOf(right));
          });

    if (filtered.isEmpty) {
      if (_match != null) _clearMatch();
      return;
    }

    setState(() {
      _match = _SlashMatch(
        nodeId: node.id,
        slashOffset: slashOffset,
        caretOffset: caretOffset,
      );
    });

    widget.controller.show(
      filteredOptions: filtered,
      onSelectOption: _applyOption,
      onDismiss: _clearMatch,
    );
    _syncMenuVisibility();
  }

  void _clearMatch() {
    if (_match != null && mounted) {
      setState(() => _match = null);
    }
    widget.controller.hide();
    if (_menuPortalController.isShowing) {
      _menuPortalController.hide();
    }
  }

  void _syncMenuVisibility() {
    if (!mounted) return;
    if (_match != null && widget.controller.isVisible) {
      _menuPortalController.show();
    } else if (_menuPortalController.isShowing) {
      _menuPortalController.hide();
    }
  }

  void _applyOption(SlashCommandOption option) {
    final match = _match;
    if (match == null) return;

    // 1. Delete the slash and query text
    widget.editor.execute([
      DeleteContentRequest(
        documentRange: DocumentRange(
          start: DocumentPosition(
            nodeId: match.nodeId,
            nodePosition: TextNodePosition(offset: match.slashOffset),
          ),
          end: DocumentPosition(
            nodeId: match.nodeId,
            nodePosition: TextNodePosition(offset: match.caretOffset),
          ),
        ),
      ),
    ]);

    // 2. Transform block
    switch (option.type) {
      case SlashOptionType.h1:
        NoteEditorCommands.setBlockType(
          widget.editor,
          widget.composer,
          header1Attribution,
        );
      case SlashOptionType.h2:
        NoteEditorCommands.setBlockType(
          widget.editor,
          widget.composer,
          header2Attribution,
        );
      case SlashOptionType.h3:
        NoteEditorCommands.setBlockType(
          widget.editor,
          widget.composer,
          header3Attribution,
        );
      case SlashOptionType.quote:
        NoteEditorCommands.setBlockType(
          widget.editor,
          widget.composer,
          blockquoteAttribution,
        );
      case SlashOptionType.task:
        NoteEditorCommands.convertToTask(widget.editor, widget.composer);
      case SlashOptionType.bulletList:
        NoteEditorCommands.convertToListItem(
          widget.editor,
          widget.composer,
          ListItemType.unordered,
        );
      case SlashOptionType.numberedList:
        NoteEditorCommands.convertToListItem(
          widget.editor,
          widget.composer,
          ListItemType.ordered,
        );
      case SlashOptionType.divider:
        NoteEditorCommands.insertDivider(widget.editor, dividerCount: 35);
      case SlashOptionType.image:
        widget.onAttachImage?.call();
      case SlashOptionType.file:
        widget.onAttachFile?.call();
    }

    // 3. Place caret correctly after transformation
    _placeCaretAfterTransform(match.nodeId, option.type);

    _clearMatch();
  }

  void _placeCaretAfterTransform(String originalNodeId, SlashOptionType type) {
    final doc = widget.editor.context.document;

    if (type == SlashOptionType.divider) {
      // Divider replaces the node — find the node after it to place caret
      final nodeIndex = doc.getNodeIndexById(originalNodeId);
      if (nodeIndex >= 0 && nodeIndex + 1 < doc.nodeCount) {
        final nextNode = doc.getNodeAt(nodeIndex + 1);
        if (nextNode is TextNode) {
          widget.editor.execute([
            ChangeSelectionRequest(
              DocumentSelection.collapsed(
                position: DocumentPosition(
                  nodeId: nextNode.id,
                  nodePosition: const TextNodePosition(offset: 0),
                ),
              ),
              SelectionChangeType.placeCaret,
              SelectionReason.userInteraction,
            ),
          ]);
        }
      }
    } else if (type == SlashOptionType.image || type == SlashOptionType.file) {
      // Attachment options handle their own flow
      return;
    } else {
      // For text block transforms (h1, h2, h3, task, list, quote),
      // the node keeps the same ID — place caret at end of text
      final node = doc.getNodeById(originalNodeId);
      if (node is TextNode) {
        final textLen = node.text.toPlainText().length;
        widget.editor.execute([
          ChangeSelectionRequest(
            DocumentSelection.collapsed(
              position: DocumentPosition(
                nodeId: originalNodeId,
                nodePosition: TextNodePosition(offset: textLen),
              ),
            ),
            SelectionChangeType.placeCaret,
            SelectionReason.userInteraction,
          ),
        ]);
      }
    }

    // Restore focus
    final focus = widget.focusNode;
    if (focus != null && !focus.hasFocus) {
      focus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: _menuPortalController,
      overlayChildBuilder: (context) => ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final options = widget.controller.filteredOptions;
          if (_match == null ||
              !widget.controller.isVisible ||
              options.isEmpty) {
            return const SizedBox.shrink();
          }

          Widget menu = _SlashMenuCard(
            options: options,
            selectedIndex: widget.controller.selectedIndex,
            onSelect: _applyOption,
          );
          final editorFocusNode = widget.focusNode;
          if (editorFocusNode != null) {
            menu = SuperEditorPopover(
              popoverFocusNode: _menuFocusNode,
              editorFocusNode: editorFocusNode,
              child: menu,
            );
          }

          return TapRegion(
            onTapOutside: (_) => _clearMatch(),
            child: Follower.withAligner(
              link: widget.selectionLayerLinks.caretLink,
              aligner: _menuAligner,
              boundary: _viewportBoundary,
              showWhenUnlinked: false,
              child: menu,
            ),
          );
        },
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _SlashMenuCard extends StatefulWidget {
  final List<SlashCommandOption> options;
  final int selectedIndex;
  final ValueChanged<SlashCommandOption> onSelect;

  const _SlashMenuCard({
    required this.options,
    required this.selectedIndex,
    required this.onSelect,
  });

  @override
  State<_SlashMenuCard> createState() => _SlashMenuCardState();
}

class _SlashMenuCardState extends State<_SlashMenuCard> {
  final ScrollController _scrollController = ScrollController();
  final Map<SlashOptionType, GlobalKey> _itemKeys = {};

  @override
  void didUpdateWidget(_SlashMenuCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    for (final option in widget.options) {
      _itemKeys.putIfAbsent(option.type, GlobalKey.new);
    }
    if (widget.selectedIndex != oldWidget.selectedIndex ||
        widget.options != oldWidget.options) {
      _scheduleScrollToSelected();
    }
  }

  void _scheduleScrollToSelected() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollToSelected();
    });
  }

  void _scrollToSelected() {
    if (!_scrollController.hasClients) return;
    if (widget.selectedIndex < 0 ||
        widget.selectedIndex >= widget.options.length) {
      return;
    }
    final itemContext =
        _itemKeys[widget.options[widget.selectedIndex].type]?.currentContext;
    if (itemContext != null) {
      Scrollable.ensureVisible(
        itemContext,
        alignment: 0.2,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final children = <Widget>[];
    String? currentGroup;

    for (var index = 0; index < widget.options.length; index++) {
      final option = widget.options[index];
      if (option.group != currentGroup) {
        currentGroup = option.group;
        children.add(
          Padding(
            padding: EdgeInsets.fromLTRB(12, index == 0 ? 8 : 10, 12, 4),
            child: Text(
              option.group,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
          ),
        );
      }

      children.add(
        _SlashMenuItem(
          key: _itemKeys.putIfAbsent(option.type, GlobalKey.new),
          option: option,
          isSelected: index == widget.selectedIndex,
          onTap: () => widget.onSelect(option),
        ),
      );
    }

    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(12),
      color: scheme.surface,
      shadowColor: scheme.shadow.withValues(alpha: 0.18),
      clipBehavior: Clip.antiAlias,
      child: Container(
        constraints: const BoxConstraints(maxHeight: 336, maxWidth: 300),
        width: 300,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: ListView(
          controller: _scrollController,
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 6),
          children: children,
        ),
      ),
    );
  }
}

class _SlashMenuItem extends StatelessWidget {
  const _SlashMenuItem({
    super.key,
    required this.option,
    required this.isSelected,
    required this.onTap,
  });

  final SlashCommandOption option;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final itemLabel = option.description == null
        ? option.label
        : '${option.label}. ${option.description}';

    return Semantics(
      button: true,
      selected: isSelected,
      label: itemLabel,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Material(
          color: isSelected
              ? scheme.primary.withValues(alpha: 0.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? scheme.primary.withValues(alpha: 0.14)
                          : scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      option.icon,
                      size: 17,
                      color: isSelected
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          option.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isSelected
                                ? scheme.primary
                                : scheme.onSurface,
                            fontSize: 12.5,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w600,
                          ),
                        ),
                        if (option.description != null)
                          Text(
                            option.description!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
