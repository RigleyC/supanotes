library;

import 'package:flutter/material.dart';
import 'package:block_editor/block_editor.dart';
import 'package:flutter/services.dart';

/// A small floating menu that appears when the drag handle of a block is
/// clicked, providing block-level operations for the target block.
///
/// [BlockActionMenu] is displayed as an [OverlayEntry] managed by
/// [BlockEditorWidget]. It is never shown when readOnly is true.
///
/// The menu provides five actions: Delete Block, Duplicate Block, Turn Into
/// (a submenu listing all registered block types), Move Up, and Move Down.
/// All actions dispatch through [BlockController].
///
/// The menu dismisses when any action is selected, when Escape is pressed,
/// or when the user taps outside the menu.
class BlockActionMenu extends StatefulWidget {
  /// Creates a [BlockActionMenu] for [blockId].
  const BlockActionMenu({
    super.key,
    required this.controller,
    required this.blockId,
    required this.globalPosition,
    required this.onDismiss,
  });

  /// The controller used to perform block operations.
  final BlockController controller;

  /// The id of the block this menu targets.
  final String blockId;

  /// The global position at which the menu should be anchored.
  final Offset globalPosition;

  /// Called when the menu should be dismissed.
  final VoidCallback onDismiss;

  @override
  State<BlockActionMenu> createState() => _BlockActionMenuState();
}

class _BlockActionMenuState extends State<BlockActionMenu> {
  bool _showTurnInto = false;
  late final FocusNode _focusNode;

  static const double _menuWidth = 200.0;
  static const double _turnIntoWidth = 200.0;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  Offset _clampedPosition(
    BuildContext context,
    Offset raw,
    double menuWidth,
    double menuHeight,
  ) {
    final screen = MediaQuery.of(context).size;
    return Offset(
      raw.dx.clamp(8.0, screen.width - menuWidth - 8.0),
      raw.dy.clamp(8.0, screen.height - menuHeight - 8.0),
    );
  }

  void _delete() {
    widget.controller.delete(widget.blockId);
    widget.onDismiss();
  }

  void _duplicate() {
    widget.controller.duplicate(widget.blockId);
    widget.onDismiss();
  }

  void _moveUp() {
    final blocks = widget.controller.document.blocks;
    final index = blocks.indexWhere((b) => b.id == widget.blockId);
    if (index <= 0) {
      widget.onDismiss();
      return;
    }
    widget.controller.move(widget.blockId, index - 1);
    widget.onDismiss();
  }

  void _moveDown() {
    final blocks = widget.controller.document.blocks;
    final index = blocks.indexWhere((b) => b.id == widget.blockId);
    if (index >= blocks.length - 1) {
      widget.onDismiss();
      return;
    }
    widget.controller.move(widget.blockId, index + 1);
    widget.onDismiss();
  }

  void _turnInto(String blockType) {
    widget.controller.transformType(widget.blockId, blockType);
    widget.onDismiss();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onDismiss();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    const mainMenuHeight = 5 * 40.0 + 8.0;
    final pos = _clampedPosition(
      context,
      widget.globalPosition,
      _menuWidth,
      mainMenuHeight,
    );

    final blocks = widget.controller.document.blocks;
    final index = blocks.indexWhere((b) => b.id == widget.blockId);
    final canMoveUp = index > 0;
    final canMoveDown = index < blocks.length - 1;

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: widget.onDismiss,
            behavior: HitTestBehavior.opaque,
            child: const ColoredBox(color: Colors.transparent),
          ),
        ),
        Positioned(
          left: pos.dx,
          top: pos.dy,
          width: _menuWidth,
          child: Focus(
            focusNode: _focusNode,
            onKeyEvent: _handleKey,
            child: Material(
              elevation: 6,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ActionItem(
                      icon: Icons.delete_outline,
                      label: 'Delete block',
                      isDestructive: true,
                      onTap: _delete,
                    ),
                    _ActionItem(
                      icon: Icons.copy_outlined,
                      label: 'Duplicate block',
                      onTap: _duplicate,
                    ),
                    _ActionItem(
                      icon: Icons.transform_outlined,
                      label: 'Turn into',
                      trailing: const Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: Color(0xFF888888),
                      ),
                      onTap: () =>
                          setState(() => _showTurnInto = !_showTurnInto),
                    ),
                    _ActionItem(
                      icon: Icons.arrow_upward,
                      label: 'Move up',
                      enabled: canMoveUp,
                      onTap: canMoveUp ? _moveUp : null,
                    ),
                    _ActionItem(
                      icon: Icons.arrow_downward,
                      label: 'Move down',
                      enabled: canMoveDown,
                      onTap: canMoveDown ? _moveDown : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (_showTurnInto)
          Positioned(
            left: (pos.dx + _menuWidth + 4.0).clamp(
              8.0,
              MediaQuery.of(context).size.width - _turnIntoWidth - 8.0,
            ),
            top: pos.dy,
            width: _turnIntoWidth,
            child: Material(
              elevation: 6,
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  children: _buildTurnIntoItems(),
                ),
              ),
            ),
          ),
      ],
    );
  }

  List<Widget> _buildTurnIntoItems() {
    final items = <Widget>[];
    for (final plugin in BlockRegistry.instance.plugins) {
      final config = plugin.slashCommandItem();
      if (config == null) continue;
      items.add(
        _ActionItem(
          icon: null,
          iconWidget: SizedBox(width: 18, height: 18, child: config.icon),
          label: config.label,
          onTap: () => _turnInto(plugin.blockType),
        ),
      );
    }
    return items;
  }
}

class _ActionItem extends StatefulWidget {
  const _ActionItem({
    required this.label,
    required this.onTap,
    this.icon,
    this.iconWidget,
    this.trailing,
    this.isDestructive = false,
    this.enabled = true,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final Widget? iconWidget;
  final Widget? trailing;
  final bool isDestructive;
  final bool enabled;

  @override
  State<_ActionItem> createState() => _ActionItemState();
}

class _ActionItemState extends State<_ActionItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final textColor = widget.isDestructive
        ? const Color(0xFFD32F2F)
        : widget.enabled
        ? color.onSurface
        : const Color(0xFF888888);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: widget.enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.enabled ? widget.onTap : null,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: widget.enabled
                ? _hovered
                      ? color.inverseSurface.withValues(alpha: 0.10)
                      : color.surface.withValues(alpha: 0.0)
                : color.surface.withValues(alpha: 0.0),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          child: Row(
            children: [
              if (widget.icon != null)
                Icon(widget.icon, size: 18, color: textColor)
              else if (widget.iconWidget != null)
                widget.iconWidget!
              else
                const SizedBox(width: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.label,
                  style: TextStyle(fontSize: 14, color: textColor),
                ),
              ),
              ?widget.trailing,
            ],
          ),
        ),
      ),
    );
  }
}
