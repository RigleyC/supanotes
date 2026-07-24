import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:super_editor/super_editor.dart';

import '../../domain/note_editor_commands.dart';
import '../../domain/slash_command_options.dart';

/// Global controller to coordinate keyboard navigation with the SlashCommandOverlay.
class SlashCommandController extends ChangeNotifier {
  static final SlashCommandController instance = SlashCommandController._();
  SlashCommandController._();

  bool _isVisible = false;
  int _selectedIndex = 0;
  List<SlashCommandOption> _filteredOptions = defaultSlashCommandOptions;
  void Function(SlashCommandOption option)? _onSelectOption;
  VoidCallback? _onDismiss;

  bool get isVisible => _isVisible;
  int get selectedIndex => _selectedIndex;
  List<SlashCommandOption> get filteredOptions => _filteredOptions;

  void updateState({
    required bool isVisible,
    required List<SlashCommandOption> filteredOptions,
    required void Function(SlashCommandOption option) onSelectOption,
    required VoidCallback onDismiss,
  }) {
    _isVisible = isVisible;
    _filteredOptions = filteredOptions;
    if (_selectedIndex >= _filteredOptions.length) {
      _selectedIndex = 0;
    }
    _onSelectOption = onSelectOption;
    _onDismiss = onDismiss;
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
        (_selectedIndex - 1 + _filteredOptions.length) % _filteredOptions.length;
    notifyListeners();
  }

  void selectCurrent() {
    if (!_isVisible || _filteredOptions.isEmpty) return;
    final option = _filteredOptions[_selectedIndex];
    _onSelectOption?.call(option);
  }

  void dismiss() {
    if (!_isVisible) return;
    _isVisible = false;
    _onDismiss?.call();
    notifyListeners();
  }
}

/// Keyboard action to intercept ArrowUp, ArrowDown, Enter, Escape when slash menu is visible.
ExecutionInstruction handleSlashMenuKeyboard({
  required SuperEditorContext editContext,
  required KeyEvent keyEvent,
}) {
  final controller = SlashCommandController.instance;
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

  return ExecutionInstruction.continueExecution;
}

class _SlashMatch {
  final String query;
  final String nodeId;
  final int slashOffset;
  final int caretOffset;

  const _SlashMatch({
    required this.query,
    required this.nodeId,
    required this.slashOffset,
    required this.caretOffset,
  });
}

class SlashCommandOverlay extends StatefulWidget {
  final Editor editor;
  final DocumentComposer composer;
  final DocumentLayout Function() documentLayoutResolver;
  final BuildContext? Function() documentLayoutContextResolver;
  final FocusNode? focusNode;
  final VoidCallback? onAttachImage;
  final VoidCallback? onAttachFile;

  const SlashCommandOverlay({
    super.key,
    required this.editor,
    required this.composer,
    required this.documentLayoutResolver,
    required this.documentLayoutContextResolver,
    this.focusNode,
    this.onAttachImage,
    this.onAttachFile,
  });

  @override
  State<SlashCommandOverlay> createState() => _SlashCommandOverlayState();
}

class _SlashCommandOverlayState extends State<SlashCommandOverlay> {
  _SlashMatch? _match;
  Rect? _caretRect;

  @override
  void initState() {
    super.initState();
    widget.composer.selectionNotifier.addListener(_updateMatch);
    _updateMatch();
  }

  @override
  void didUpdateWidget(SlashCommandOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.composer != oldWidget.composer) {
      oldWidget.composer.selectionNotifier.removeListener(_updateMatch);
      widget.composer.selectionNotifier.addListener(_updateMatch);
      _updateMatch();
    }
  }

  @override
  void dispose() {
    widget.composer.selectionNotifier.removeListener(_updateMatch);
    SlashCommandController.instance.dismiss();
    super.dispose();
  }

  void _updateMatch() {
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

    // Detect "/" at start of paragraph (or preceded only by whitespace)
    final textBeforeCaret = text.substring(0, caretOffset);
    final match = RegExp(r'^\s*\/([a-zA-Z0-9_-]*)$').firstMatch(textBeforeCaret);

    if (match == null) {
      if (_match != null) _clearMatch();
      return;
    }

    final slashOffset = textBeforeCaret.lastIndexOf('/');
    final query = match.group(1) ?? '';
    final filtered = defaultSlashCommandOptions
        .where((opt) => opt.matches(query))
        .toList();

    if (filtered.isEmpty) {
      if (_match != null) _clearMatch();
      return;
    }

    // Resolve caret position in local overlay coordinate space safely
    try {
      final docLayout = widget.documentLayoutResolver();
      final docContext = widget.documentLayoutContextResolver();
      final docBox = docContext?.findRenderObject() as RenderBox?;
      if (docBox != null && docBox.attached) {
        final caretInDoc = docLayout.getRectForPosition(position);
        if (caretInDoc != null) {
          final globalCaretTopLeft =
              docBox.localToGlobal(caretInDoc.topLeft);
          final overlayBox = context.findRenderObject() as RenderBox?;
          if (overlayBox != null && overlayBox.attached) {
            final overlayTopLeft =
                overlayBox.globalToLocal(globalCaretTopLeft);
            _caretRect = Rect.fromLTWH(
              overlayTopLeft.dx,
              overlayTopLeft.dy,
              caretInDoc.width,
              caretInDoc.height,
            );
          }
        }
      }
    } catch (_) {
      _caretRect = null;
    }

    setState(() {
      _match = _SlashMatch(
        query: query,
        nodeId: node.id,
        slashOffset: slashOffset,
        caretOffset: caretOffset,
      );
    });

    SlashCommandController.instance.updateState(
      isVisible: true,
      filteredOptions: filtered,
      onSelectOption: _applyOption,
      onDismiss: _clearMatch,
    );
  }

  void _clearMatch() {
    setState(() {
      _match = null;
      _caretRect = null;
    });
    SlashCommandController.instance.updateState(
      isVisible: false,
      filteredOptions: [],
      onSelectOption: (_) {},
      onDismiss: () {},
    );
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

    // 2. Transform block using NoteEditorCommands
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

    // 3. Place caret at end of current node text and restore focus
    final node = widget.editor.context.document.getNodeById(match.nodeId);
    final textOffset = node is TextNode ? node.text.toPlainText().length : 0;
    widget.editor.execute([
      ChangeSelectionRequest(
        DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: match.nodeId,
            nodePosition: TextNodePosition(offset: textOffset),
          ),
        ),
        SelectionChangeType.placeCaret,
        SelectionReason.userInteraction,
      ),
    ]);

    final focus = widget.focusNode;
    if (focus != null && !focus.hasFocus) {
      focus.requestFocus();
    }

    _clearMatch();
  }

  @override
  Widget build(BuildContext context) {
    if (_match == null) return const SizedBox.shrink();

    final caretRect = _caretRect;

    return ListenableBuilder(
      listenable: SlashCommandController.instance,
      builder: (context, _) {
        final controller = SlashCommandController.instance;
        final options = controller.filteredOptions;
        if (!controller.isVisible || options.isEmpty) {
          return const SizedBox.shrink();
        }

        final menuCard = _SlashMenuCard(
          options: options,
          selectedIndex: controller.selectedIndex,
          onSelect: _applyOption,
        );

        final overlayBox = context.findRenderObject() as RenderBox?;
        final overlaySize =
            overlayBox?.hasSize == true ? overlayBox!.size : null;

        double left = 32.0;
        double top = 80.0;
        const menuWidth = 260.0;
        const estimatedMenuHeight = 240.0;

        if (caretRect != null && overlaySize != null) {
          left = caretRect.left;
          top = caretRect.bottom + 6.0; // Place below caret by default

          final spaceBelow = overlaySize.height - caretRect.bottom;
          final spaceAbove = caretRect.top;

          // Flip above ONLY if space below is insufficient and space above is greater
          if (spaceBelow < estimatedMenuHeight && spaceAbove > spaceBelow) {
            top = (caretRect.top - estimatedMenuHeight - 6.0)
                .clamp(16.0, overlaySize.height - 60.0);
          }

          // Clamp horizontally to stay inside visible bounds
          left = left.clamp(
            16.0,
            (overlaySize.width - menuWidth - 16.0).clamp(16.0, double.infinity),
          );
        }

        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              child: menuCard,
            ),
          ],
        );
      },
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

  @override
  void didUpdateWidget(_SlashMenuCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedIndex != oldWidget.selectedIndex) {
      _scrollToIndex(widget.selectedIndex);
    }
  }

  void _scrollToIndex(int index) {
    if (!_scrollController.hasClients) return;
    const itemExtent = 40.0;
    final targetTop = index * itemExtent;
    final targetBottom = targetTop + itemExtent;

    final currentOffset = _scrollController.offset;
    final viewportHeight = _scrollController.position.viewportDimension;

    if (targetTop < currentOffset) {
      _scrollController.animateTo(
        targetTop,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
      );
    } else if (targetBottom > currentOffset + viewportHeight) {
      _scrollController.animateTo(
        targetBottom - viewportHeight + 12,
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

    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(12),
      color: scheme.surfaceContainerHigh,
      shadowColor: Colors.black26,
      child: Container(
        constraints: const BoxConstraints(maxHeight: 280, maxWidth: 260),
        width: 260,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: ListView.builder(
          controller: _scrollController,
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 6),
          itemCount: widget.options.length,
          itemBuilder: (context, index) {
            final option = widget.options[index];
            final isSelected = index == widget.selectedIndex;
            return InkWell(
              onTap: () => widget.onSelect(option),
              child: Container(
                color: isSelected
                    ? scheme.primary.withValues(alpha: 0.12)
                    : Colors.transparent,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      option.icon,
                      size: 18,
                      color: isSelected ? scheme.primary : scheme.onSurface,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        option.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.w500,
                          color: isSelected ? scheme.primary : scheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
