library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:block_editor/block_editor.dart';

const List<Color> _kPaletteColors = [
  Colors.black,
  Colors.white,
  Color(0xFF9E9E9E),
  Color(0xFFF44336),
  Color(0xFFE91E63),
  Color(0xFF9C27B0),
  Color(0xFF2196F3),
  Color(0xFF4CAF50),
  Color(0xFFFF9800),
  Color(0xFFFFEB3B),
  Color(0xFF00BCD4),
  Color(0xFF795548),
];

String _colorToHex(Color color) {
  final r = (color.r * 255).round().toRadixString(16).padLeft(2, '0');
  final g = (color.g * 255).round().toRadixString(16).padLeft(2, '0');
  final b = (color.b * 255).round().toRadixString(16).padLeft(2, '0');
  return '#$r$g$b';
}

Color? _hexToColor(String? hex) {
  if (hex == null) return null;
  try {
    return Color(int.parse(hex.replaceFirst('#', '0xFF')));
  } catch (_) {
    return null;
  }
}

enum _AttributeState { inactive, active, mixed }

class _SelectionAttributes {
  const _SelectionAttributes({
    required this.bold,
    required this.italic,
    required this.underline,
    required this.strikethrough,
    required this.inlineCode,
    required this.link,
    required this.textColor,
    required this.backgroundColor,
  });

  final _AttributeState bold;
  final _AttributeState italic;
  final _AttributeState underline;
  final _AttributeState strikethrough;
  final _AttributeState inlineCode;
  final _AttributeState link;
  final _AttributeState textColor;
  final _AttributeState backgroundColor;

  static _SelectionAttributes resolve(
    ExpandedSelection sel,
    BlockDocument document,
  ) {
    final ids = document.flatten().map((b) => b.id).toList();
    final resolved = sel.resolveOrder(ids);
    final ops = <TextOp>[];

    if (resolved.start.blockId == resolved.end.blockId) {
      final node = document.findById(resolved.start.blockId);
      if (node != null) {
        ops.addAll(
          _opsInRange(node, resolved.start.offset, resolved.end.offset),
        );
      }
    } else {
      final allBlocks = document.flatten();
      final startIndex = allBlocks.indexWhere(
        (b) => b.id == resolved.start.blockId,
      );
      final endIndex = allBlocks.indexWhere(
        (b) => b.id == resolved.end.blockId,
      );
      final startNode = document.findById(resolved.start.blockId);
      if (startNode != null) {
        final len = startNode.delta?.plainText.length ?? 0;
        ops.addAll(_opsInRange(startNode, resolved.start.offset, len));
      }
      for (var i = startIndex + 1; i < endIndex; i++) {
        final node = allBlocks[i];
        final len = node.delta?.plainText.length ?? 0;
        ops.addAll(_opsInRange(node, 0, len));
      }
      final endNode = document.findById(resolved.end.blockId);
      if (endNode != null) {
        ops.addAll(_opsInRange(endNode, 0, resolved.end.offset));
      }
    }

    if (ops.isEmpty) {
      return const _SelectionAttributes(
        bold: _AttributeState.inactive,
        italic: _AttributeState.inactive,
        underline: _AttributeState.inactive,
        strikethrough: _AttributeState.inactive,
        inlineCode: _AttributeState.inactive,
        link: _AttributeState.inactive,
        textColor: _AttributeState.inactive,
        backgroundColor: _AttributeState.inactive,
      );
    }

    return _SelectionAttributes(
      bold: _stateFor(ops, (a) => a.bold == true),
      italic: _stateFor(ops, (a) => a.italic == true),
      underline: _stateFor(ops, (a) => a.underline == true),
      strikethrough: _stateFor(ops, (a) => a.strikethrough == true),
      inlineCode: _stateFor(ops, (a) => a.inlineCode == true),
      link: _stateFor(ops, (a) => a.link != null),
      textColor: _stateFor(ops, (a) => a.color != null),
      backgroundColor: _stateFor(ops, (a) => a.backgroundColor != null),
    );
  }

  static List<TextOp> _opsInRange(BlockNode node, int start, int end) {
    if (start >= end) return const [];
    final delta = node.delta;
    if (delta == null) return const [];
    final result = <TextOp>[];
    var cursor = 0;
    for (final op in delta.ops) {
      if (op is! TextOp) {
        cursor++;
        continue;
      }
      final opEnd = cursor + op.text.length;
      if (opEnd > start && cursor < end) result.add(op);
      cursor = opEnd;
    }
    return result;
  }

  static _AttributeState _stateFor(
    List<TextOp> ops,
    bool Function(InlineAttributes) test,
  ) {
    final count = ops.where((op) => test(op.attributes)).length;
    if (count == 0) return _AttributeState.inactive;
    if (count == ops.length) return _AttributeState.active;
    return _AttributeState.mixed;
  }
}

/// A context-sensitive formatting toolbar that appears over selected text.
///
/// [FormattingToolbar] is placed inside an [OverlayPortal] owned by
/// [BlockEditorWidget] and is only shown when the editor has an active
/// [ExpandedSelection] and readOnly is false.
///
/// **Display modes** are determined by comparing [availableWidth] to
/// [toolbarBreakpoint]. When the editor is wide, the toolbar floats above the
/// anchor block's render box. When narrow or when no anchor position can be
/// resolved, it pins to the bottom of the editor's own render box.
///
/// **Attribute state** — each of the eight buttons reflects whether the
/// entire selection has the attribute (active), none of it does (inactive),
/// or only part does (mixed).
///
/// **Color buttons** — when [onColorPickerRequested] is null a built-in
/// 12-swatch palette popover opens. When non-null the callback is awaited
/// and the returned [Color] is applied if non-null. Colors are stored and
/// applied as `#RRGGBB` hex strings in [InlineAttributes].
class FormattingToolbar extends StatefulWidget {
  /// Creates a [FormattingToolbar].
  ///
  /// [anchorKey] is the [GlobalKey] of the block that anchors the floating
  /// position. May be null, in which case the bottom-pin fallback is used.
  const FormattingToolbar({
    super.key,
    required this.controller,
    required this.ops,
    required this.anchorKey,
    required this.editorKey,
    required this.toolbarBreakpoint,
    required this.availableWidth,
    this.onColorPickerRequested,
  });

  /// The controller whose selection and document state are read.
  final BlockController controller;

  /// The editing operations delegate used to apply inline formatting.
  final EditorEditingOperations ops;

  /// The [GlobalKey] of the anchor block widget for wide-screen positioning.
  final GlobalKey? anchorKey;

  /// The [GlobalKey] of the [BlockEditorWidget] for narrow-screen positioning.
  final GlobalKey editorKey;

  /// Width threshold in logical pixels controlling display mode.
  final double toolbarBreakpoint;

  /// Current available width of the editor in logical pixels.
  final double availableWidth;

  /// Optional callback for custom color pickers.
  ///
  /// Receives the current color of the selection as a [Color] converted from
  /// the stored hex string, or null if no color is set. When non-null this is
  /// awaited and the returned [Color] is converted to a `#RRGGBB` hex string
  /// and applied. When null the built-in palette popover is used.
  final Future<Color?> Function(Color? currentColor)? onColorPickerRequested;

  @override
  State<FormattingToolbar> createState() => _FormattingToolbarState();
}

class _FormattingToolbarState extends State<FormattingToolbar> {
  OverlayEntry? _paletteEntry;

  static const double _toolbarWidth = 336.0;
  static const double _toolbarHeight = 44.0;

  @override
  void dispose() {
    _paletteEntry?.remove();
    _paletteEntry = null;
    super.dispose();
  }

  Offset _computePosition(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isWide = widget.availableWidth >= widget.toolbarBreakpoint;

    if (isWide && widget.anchorKey != null) {
      final anchorBox =
          widget.anchorKey!.currentContext?.findRenderObject() as RenderBox?;
      if (anchorBox != null && anchorBox.hasSize) {
        final global = anchorBox.localToGlobal(Offset.zero);
        final rawX = global.dx + anchorBox.size.width / 2 - _toolbarWidth / 2;
        final x = rawX.clamp(8.0, screenSize.width - _toolbarWidth - 8.0);
        final y = (global.dy - _toolbarHeight - 8.0).clamp(
          8.0,
          screenSize.height - _toolbarHeight - 8.0,
        );
        return Offset(x, y);
      }
    }

    final editorBox =
        widget.editorKey.currentContext?.findRenderObject() as RenderBox?;
    if (editorBox != null && editorBox.hasSize) {
      final global = editorBox.localToGlobal(Offset.zero);
      final rawX = global.dx + editorBox.size.width / 2 - _toolbarWidth / 2;
      return Offset(
        rawX.clamp(8.0, screenSize.width - _toolbarWidth - 8.0),
        (global.dy + editorBox.size.height - _toolbarHeight).clamp(
          8.0,
          screenSize.height - _toolbarHeight - 8.0,
        ),
      );
    }

    return Offset(
      (screenSize.width - _toolbarWidth) / 2,
      screenSize.height - _toolbarHeight - 16.0,
    );
  }

  Future<void> _handleColorButton({required bool isBackground}) async {
    final sel = widget.controller.selection;
    if (sel is! ExpandedSelection) return;

    final ids = widget.controller.document.flatten().map((b) => b.id).toList();
    final resolved = sel.resolveOrder(ids);
    final node = widget.controller.document.findById(resolved.start.blockId);

    String? currentHex;
    if (node?.delta != null) {
      for (final op in node!.delta!.ops) {
        if (op is TextOp) {
          currentHex = isBackground
              ? op.attributes.backgroundColor
              : op.attributes.color;
          break;
        }
      }
    }

    if (widget.onColorPickerRequested != null) {
      final picked = await widget.onColorPickerRequested!(
        _hexToColor(currentHex),
      );
      if (picked != null && mounted) {
        _applyColorHex(_colorToHex(picked), isBackground: isBackground);
      }
      return;
    }

    if (!mounted) return;
    _showPalette(currentHex: currentHex, isBackground: isBackground);
  }

  void _showPalette({required String? currentHex, required bool isBackground}) {
    _paletteEntry?.remove();
    _paletteEntry = null;
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _PalettePopover(
        currentHex: currentHex,
        onColorSelected: (color) {
          entry.remove();
          _paletteEntry = null;
          _applyColorHex(_colorToHex(color), isBackground: isBackground);
        },
        onDismiss: () {
          entry.remove();
          _paletteEntry = null;
        },
      ),
    );
    _paletteEntry = entry;
    Overlay.of(context).insert(entry);
  }

  void _applyColorHex(String hex, {required bool isBackground}) {
    final attrs = isBackground
        ? InlineAttributes(backgroundColor: hex)
        : InlineAttributes(color: hex);
    widget.ops.applyAttributes(attrs);
  }

  @override
  Widget build(BuildContext context) {
    final sel = widget.controller.selection;
    if (sel is! ExpandedSelection) return const SizedBox.shrink();

    final attrs = _SelectionAttributes.resolve(sel, widget.controller.document);
    final position = _computePosition(context);

    return Positioned(
      left: position.dx,
      top: position.dy,
      width: _toolbarWidth,
      height: _toolbarHeight,
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _ToolbarButton(
              icon: Icons.format_bold,
              label: 'Bold',
              state: attrs.bold,
              onPressed: widget.ops.applyBold,
            ),
            _ToolbarButton(
              icon: Icons.format_italic,
              label: 'Italic',
              state: attrs.italic,
              onPressed: widget.ops.applyItalic,
            ),
            _ToolbarButton(
              icon: Icons.format_underline,
              label: 'Underline',
              state: attrs.underline,
              onPressed: widget.ops.applyUnderline,
            ),
            _ToolbarButton(
              icon: Icons.format_strikethrough,
              label: 'Strikethrough',
              state: attrs.strikethrough,
              onPressed: widget.ops.applyStrikethrough,
            ),
            _ToolbarButton(
              icon: Icons.code,
              label: 'Inline code',
              state: attrs.inlineCode,
              onPressed: widget.ops.applyInlineCode,
            ),
            _ToolbarButton(
              icon: Icons.link,
              label: 'Link',
              state: attrs.link,
              onPressed: () => widget.ops.applyLink(''),
            ),
            _ToolbarButton(
              icon: Icons.format_color_text,
              label: 'Text color',
              state: attrs.textColor,
              onPressed: () => _handleColorButton(isBackground: false),
            ),
            _ToolbarButton(
              icon: Icons.format_color_fill,
              label: 'Background color',
              state: attrs.backgroundColor,
              onPressed: () => _handleColorButton(isBackground: true),
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
    required this.label,
    required this.state,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final _AttributeState state;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final isActive = state == _AttributeState.active;
    final isMixed = state == _AttributeState.mixed;
    final color = Theme.of(context).colorScheme;

    return Tooltip(
      message: label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onPressed,
          child: AnimatedContainer(
            width: 36,
            height: 36,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeInOutCubic,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: isActive
                  ? color.inverseSurface.withValues(alpha: 0.10)
                  : color.surface.withValues(alpha: 0.0),
            ),
            child: Icon(
              icon,
              size: 18,
              color: isMixed ? color.onInverseSurface : color.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

class _PalettePopover extends StatelessWidget {
  const _PalettePopover({
    required this.currentHex,
    required this.onColorSelected,
    required this.onDismiss,
  });

  final String? currentHex;
  final void Function(Color) onColorSelected;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onDismiss,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        children: [
          Positioned.fill(child: Container(color: Colors.transparent)),
          Center(
            child: GestureDetector(
              onTap: () {},
              child: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(8),
                color: const Color(0xFF2C2C2C),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      ..._kPaletteColors.map(
                        (color) => _Swatch(
                          color: color,
                          isSelected: currentHex == _colorToHex(color),
                          onTap: () => onColorSelected(color),
                        ),
                      ),
                      _Swatch(
                        color: Colors.transparent,
                        isSelected: currentHex == null,
                        onTap: () => onColorSelected(Colors.transparent),
                        isClear: true,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.isSelected,
    required this.onTap,
    this.isClear = false,
  });

  final Color color;
  final bool isSelected;
  final VoidCallback onTap;
  final bool isClear;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: isClear ? null : color,
          border: Border.all(
            color: isSelected ? Colors.white : const Color(0xFF555555),
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: isClear
            ? const Icon(Icons.format_clear, size: 16, color: Color(0xFFEEEEEE))
            : null,
      ),
    );
  }
}
