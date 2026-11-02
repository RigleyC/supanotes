library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:block_editor/block_editor.dart';

const List<String> _kBuiltInGroupOrder = [
  'Text',
  'Headings',
  'Lists',
  'Media',
  'Embeds',
  'Advanced',
];

/// A floating menu that appears when the user types `/` at the start of an
/// empty block or immediately after a space, listing all block types
/// registered in [BlockRegistry] that declare a [SlashCommandConfig] with
/// a `'/'` trigger.
///
/// Entries are grouped by [BlockPlugin.slashCommandGroup]. Built-in groups
/// appear in the fixed order: Text, Headings, Lists, Media, Embeds, Advanced.
/// External groups appear after, sorted alphabetically. Entries whose group
/// is null appear under "Other".
///
/// The menu claims keyboard focus when shown via [FocusNode.requestFocus] in
/// initState. On dismissal it returns focus to [editorFocusNode]. This
/// ensures all keyboard events — arrow navigation, Enter, Tab, Escape,
/// Backspace, and character input — are handled by the menu while it is open.
///
/// On confirmation the menu strips the `/` character and any filter text from
/// the triggering block, then either transforms the current block to the
/// selected type (when the block is otherwise empty) or inserts a new block
/// of that type immediately below (when the block has other content). The
/// plugin's own [SlashCommandConfig.onSelected] callback is then called.
class SlashCommandMenu extends StatefulWidget {
  /// Creates a [SlashCommandMenu].
  const SlashCommandMenu({
    super.key,
    required this.controller,
    required this.ops,
    required this.anchorKey,
    required this.editorKey,
    required this.editorFocusNode,
    required this.triggerBlockId,
    required this.triggerOffset,
    required this.onDismiss,
  });

  /// The controller used to read document state and perform block operations.
  final BlockController controller;

  /// The editing operations delegate.
  final EditorEditingOperations ops;

  /// The [GlobalKey] of the block widget that triggered the menu.
  final GlobalKey? anchorKey;

  /// The [GlobalKey] of the [BlockEditorWidget] for fallback positioning.
  final GlobalKey editorKey;

  /// The [FocusNode] of [BlockEditorWidget].
  ///
  /// Focus is returned to this node when the menu is dismissed.
  final FocusNode editorFocusNode;

  /// The id of the block in which `/` was typed.
  final String triggerBlockId;

  /// The character offset immediately after the `/` character was inserted.
  final int triggerOffset;

  /// Called when the menu should be hidden without performing any insertion.
  final VoidCallback onDismiss;

  @override
  State<SlashCommandMenu> createState() => _SlashCommandMenuState();
}

class _SlashCommandMenuState extends State<SlashCommandMenu> {
  late final FocusNode _focusNode;
  late List<_MenuEntry> _allEntries;
  late List<_MenuEntry> _filtered;
  int _highlighted = 0;
  String _filter = '';

  static const double _menuWidth = 280.0;
  static const double _maxMenuHeight = 320.0;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _allEntries = _buildEntries();
    _filtered = List.of(_allEntries);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _dismiss() {
    widget.onDismiss();
    widget.editorFocusNode.requestFocus();
  }

  List<_MenuEntry> _buildEntries() {
    final entries = <_MenuEntry>[];
    final seen = <String>{};

    for (final plugin in BlockRegistry.instance.plugins) {
      final config = plugin.slashCommandItem();
      if (config == null || config.trigger != '/') continue;
      if (seen.contains(plugin.blockType)) continue;
      seen.add(plugin.blockType);
      final group = plugin.slashCommandGroup() ?? config.group ?? 'Other';
      entries.add(
        _MenuEntry(blockType: plugin.blockType, config: config, group: group),
      );
    }

    entries.sort((a, b) {
      final ai = _groupSortKey(a.group);
      final bi = _groupSortKey(b.group);
      if (ai != bi) return ai.compareTo(bi);
      return a.config.label.compareTo(b.config.label);
    });

    return entries;
  }

  int _groupSortKey(String group) {
    final i = _kBuiltInGroupOrder.indexOf(group);
    return i >= 0 ? i : _kBuiltInGroupOrder.length;
  }

  void _applyFilter(String query) {
    setState(() {
      _filter = query;
      final lower = query.toLowerCase();
      _filtered = _allEntries.where((e) {
        return e.config.label.toLowerCase().contains(lower) ||
            (e.config.description?.toLowerCase().contains(lower) ?? false) ||
            e.group.toLowerCase().contains(lower);
      }).toList();
      _highlighted = 0;
    });
  }

  void _confirm(_MenuEntry entry) {
    _execute(entry);
    _dismiss();
  }

  void _execute(_MenuEntry entry) {
    final blockId = widget.triggerBlockId;
    final node = widget.controller.document.findById(blockId);
    if (node == null) return;

    final fullText = node.delta?.plainText ?? '';
    final slashPos = widget.triggerOffset - 1;
    final removeStart = slashPos < 0 ? 0 : slashPos;

    if (removeStart < fullText.length) {
      final trimmed = (node.delta ?? TextDelta.empty()).slice(0, removeStart);
      widget.controller.updateDelta(blockId, trimmed);
    }

    final updatedNode = widget.controller.document.findById(blockId);
    final isEmpty =
        updatedNode?.delta == null || updatedNode!.delta!.plainText.isEmpty;

    if (isEmpty) {
      widget.controller.transformType(blockId, entry.blockType);
      widget.controller.collapseSelection(blockId, 0);
    } else {
      final blocks = widget.controller.document.blocks;
      final index = blocks.indexWhere((b) => b.id == blockId);
      final newNode = BlockNode(type: entry.blockType);
      widget.controller.insertAt(index + 1, newNode);
      widget.controller.collapseSelection(newNode.id, 0);
    }

    entry.config.onSelected();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.escape) {
      _dismiss();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      if (_filtered.isNotEmpty) {
        setState(() {
          _highlighted = (_highlighted + 1).clamp(0, _filtered.length - 1);
        });
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      if (_filtered.isNotEmpty) {
        setState(() {
          _highlighted = (_highlighted - 1).clamp(0, _filtered.length - 1);
        });
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.tab) {
      if (_filtered.isNotEmpty) {
        _confirm(_filtered[_highlighted]);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.backspace) {
      if (_filter.isEmpty) {
        _dismiss();
      } else {
        widget.ops.backspace();
        _applyFilter(_filter.substring(0, _filter.length - 1));
      }
      return KeyEventResult.handled;
    }
    if (event.character != null) {
      final char = event.character!;
      final code = char.codeUnitAt(0);
      if (code >= 32 && code != 127) {
        widget.ops.insertCharacter(char);
        _applyFilter(_filter + char);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  Offset _computePosition(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    if (widget.anchorKey != null) {
      final box =
          widget.anchorKey!.currentContext?.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize) {
        final global = box.localToGlobal(Offset.zero);
        final rawX = global.dx.clamp(8.0, screenSize.width - _menuWidth - 8.0);
        final spaceBelow =
            screenSize.height - (global.dy + box.size.height) - 8.0;
        final y = spaceBelow >= _maxMenuHeight
            ? global.dy + box.size.height + 4.0
            : (global.dy - _maxMenuHeight - 4.0).clamp(
                8.0,
                screenSize.height - _maxMenuHeight - 8.0,
              );
        return Offset(rawX, y);
      }
    }

    final editorBox =
        widget.editorKey.currentContext?.findRenderObject() as RenderBox?;
    if (editorBox != null && editorBox.hasSize) {
      final global = editorBox.localToGlobal(Offset.zero);
      return Offset(
        (global.dx + 16.0).clamp(8.0, screenSize.width - _menuWidth - 8.0),
        (global.dy + editorBox.size.height / 2).clamp(
          8.0,
          screenSize.height - _maxMenuHeight - 8.0,
        ),
      );
    }

    return Offset(
      (screenSize.width - _menuWidth) / 2,
      screenSize.height / 2 - _maxMenuHeight / 2,
    );
  }

  @override
  Widget build(BuildContext context) {
    final position = _computePosition(context);

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: _dismiss,
            behavior: HitTestBehavior.opaque,
            child: const ColoredBox(color: Colors.transparent),
          ),
        ),
        Positioned(
          left: position.dx,
          top: position.dy,
          width: _menuWidth,
          child: Focus(
            focusNode: _focusNode,
            onKeyEvent: _handleKey,
            child: Material(
              elevation: 6,
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: _maxMenuHeight),
                child: _filtered.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'No results',
                          style: TextStyle(
                            color: Color(0xFF888888),
                            fontSize: 14,
                          ),
                        ),
                      )
                    : _buildList(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildList() {
    final rows = <Widget>[];
    String? lastGroup;
    var entryIndex = 0;

    for (final entry in _filtered) {
      if (entry.group != lastGroup) {
        rows.add(_GroupHeader(label: entry.group));
        lastGroup = entry.group;
      }
      final i = entryIndex;
      rows.add(
        _EntryRow(
          entry: entry,
          isHighlighted: i == _highlighted,
          onTap: () => _confirm(entry),
          onHover: () => setState(() => _highlighted = i),
        ),
      );
      entryIndex++;
    }

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: rows,
    );
  }
}

class _MenuEntry {
  const _MenuEntry({
    required this.blockType,
    required this.config,
    required this.group,
  });

  final String blockType;
  final SlashCommandConfig config;
  final String group;
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: Color(0xFF888888),
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.entry,
    required this.isHighlighted,
    required this.onTap,
    required this.onHover,
  });

  final _MenuEntry entry;
  final bool isHighlighted;
  final VoidCallback onTap;
  final VoidCallback onHover;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;

    return MouseRegion(
      onEnter: (_) => onHover(),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: isHighlighted
                ? color.inverseSurface.withValues(alpha: 0.10)
                : color.surface.withValues(alpha: 0.0),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(width: 24, height: 24, child: entry.config.icon),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.config.label,
                      style: TextStyle(fontSize: 14, color: color.onSurface),
                    ),
                    if (entry.config.description != null)
                      Text(
                        entry.config.description!,
                        style: TextStyle(fontSize: 12, color: color.onSurface),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
