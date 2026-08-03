import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:super_editor/super_editor.dart';

import 'package:supanotes/features/notes/editor/document/note_editor_commands.dart';
import 'package:supanotes/features/notes/editor/document/slash_command_options.dart';

/// Keyboard action to intercept ArrowUp, ArrowDown, Enter, Escape when slash menu is visible.
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
    if (_selectedIndex >= _filteredOptions.length) {
      _selectedIndex = 0;
    }
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
  final SlashCommandController controller;
  final FocusNode? focusNode;
  final VoidCallback? onAttachImage;
  final VoidCallback? onAttachFile;

  const SlashCommandOverlay({
    super.key,
    required this.editor,
    required this.composer,
    required this.documentLayoutResolver,
    required this.documentLayoutContextResolver,
    required this.controller,
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
    widget.composer.selectionNotifier.addListener(_onSelectionChanged);
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
    final filtered = defaultSlashCommandOptions
        .where((opt) => opt.matches(query))
        .toList();

    if (filtered.isEmpty) {
      if (_match != null) _clearMatch();
      return;
    }

    setState(() {
      _match = _SlashMatch(
        query: query,
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

    // Calculate caret rect after layout updates
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _match == null) return;
      _updateCaretRect(position);
    });
  }

  void _updateCaretRect(DocumentPosition position) {
    try {
      final docLayout = widget.documentLayoutResolver();
      final docContext = widget.documentLayoutContextResolver();
      final docBox = docContext?.findRenderObject() as RenderBox?;
      if (docBox != null && docBox.attached) {
        final caretInDoc = docLayout.getRectForPosition(position);
        if (caretInDoc != null) {
          final globalCaretTopLeft = docBox.localToGlobal(caretInDoc.topLeft);
          final overlayBox = context.findRenderObject() as RenderBox?;
          if (overlayBox != null && overlayBox.attached) {
            final overlayTopLeft = overlayBox.globalToLocal(globalCaretTopLeft);
            setState(() {
              _caretRect = Rect.fromLTWH(
                overlayTopLeft.dx,
                overlayTopLeft.dy,
                caretInDoc.width,
                caretInDoc.height,
              );
            });
          }
        }
      }
    } catch (_) {
      // Layout not ready yet, ignore
    }
  }

  void _clearMatch() {
    setState(() {
      _match = null;
      _caretRect = null;
    });
    widget.controller.hide();
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
    if (_match == null) return const SizedBox.shrink();

    final caretRect = _caretRect;

    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final options = widget.controller.filteredOptions;
        if (!widget.controller.isVisible || options.isEmpty) {
          return const SizedBox.shrink();
        }

        final menuCard = _SlashMenuCard(
          options: options,
          selectedIndex: widget.controller.selectedIndex,
          onSelect: _applyOption,
        );

        final overlayBox = context.findRenderObject() as RenderBox?;
        final overlaySize = overlayBox?.hasSize == true
            ? overlayBox!.size
            : null;

        double left = 32.0;
        double top = 80.0;
        const menuWidth = 260.0;
        const estimatedMenuHeight = 240.0;

        if (caretRect != null && overlaySize != null) {
          left = caretRect.left;
          top = caretRect.bottom + 6.0;

          final spaceBelow = overlaySize.height - caretRect.bottom;
          final spaceAbove = caretRect.top;

          if (spaceBelow < estimatedMenuHeight && spaceAbove > spaceBelow) {
            top = (caretRect.top - estimatedMenuHeight - 6.0).clamp(
              16.0,
              overlaySize.height - 60.0,
            );
          }

          left = left.clamp(
            16.0,
            (overlaySize.width - menuWidth - 16.0).clamp(16.0, double.infinity),
          );
        }

        return Stack(
          children: [
            // Invisible tap catcher to dismiss menu
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _clearMatch,
              ),
            ),
            Positioned(left: left, top: top, child: menuCard),
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
      shadowColor: scheme.shadow.withValues(alpha: 0.26),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
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
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.w500,
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
