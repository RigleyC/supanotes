library;

import 'package:flutter/material.dart';
import 'package:block_editor/block_editor.dart';

/// Drives a blinking cursor animation for the block identified by [blockId].
///
/// [BlockCursor] owns the blink [AnimationController] and passes an animated
/// [Color] (with varying opacity) into its [child] subtree via
/// [CursorColorScope]. Every [RichTextRenderer] in the subtree reads the
/// animated color from scope and paints its own caret when [selection] is a
/// [CollapsedSelection] pointing at its block.
///
/// This design keeps all cursor measurement inside [RichTextRenderer], which
/// already knows its [baseStyle], [delta], and variables — the only data
/// needed for pixel-accurate caret placement.
///
/// The blink animation is part of the public API. Supply a custom
/// [Animation<double>] via [animation] to override the default breathing
/// fade. The animation value must be in the range [0.0, 1.0] where 1.0 is
/// fully opaque.
class BlockCursor extends StatefulWidget {
  /// Creates a [BlockCursor] for the block identified by [blockId].
  const BlockCursor({
    super.key,
    required this.blockId,
    required this.delta,
    required this.selection,
    this.baseStyle,
    this.cursorColor = const Color(0xFF000000),
    this.cursorWidth = 2.0,
    this.animation,
    this.blinkDuration = const Duration(milliseconds: 1200),
    this.child,
  });

  /// The id of the block this cursor belongs to.
  final String blockId;

  /// The inline content of the block.
  final TextDelta delta;

  /// The current editor selection.
  final EditorSelection selection;

  /// Unused — retained for API compatibility. Each [RichTextRenderer] uses
  /// its own [baseStyle].
  final TextStyle? baseStyle;

  /// The base color of the cursor line.
  final Color cursorColor;

  /// The width of the cursor line in logical pixels.
  final double cursorWidth;

  /// An optional external animation that drives cursor opacity.
  final Animation<double>? animation;

  /// The duration of one full blink cycle when using the default animation.
  final Duration blinkDuration;

  /// The subtree to render beneath the cursor.
  final Widget? child;

  @override
  State<BlockCursor> createState() => _BlockCursorState();
}

class _BlockCursorState extends State<BlockCursor>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    if (widget.animation == null) {
      _controller = AnimationController(
        vsync: this,
        duration: widget.blinkDuration ~/ 2,
      )..repeat(reverse: true);
      _animation = CurvedAnimation(
        parent: _controller!,
        curve: Curves.easeInOut,
      );
    } else {
      _animation = widget.animation!;
    }
  }

  @override
  void didUpdateWidget(BlockCursor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animation != null) {
      _animation = widget.animation!;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  bool get _shouldShowCursor {
    final sel = widget.selection;
    if (sel is! CollapsedSelection) return false;
    return sel.point.blockId == widget.blockId;
  }

  @override
  Widget build(BuildContext context) {
    final child =
        widget.child ??
        RichTextRenderer(
          delta: widget.delta,
          blockId: widget.blockId,
          selection: widget.selection,
          baseStyle: widget.baseStyle,
        );

    if (!_shouldShowCursor) return child;

    return AnimatedBuilder(
      animation: _animation,
      builder: (_, inner) => CursorColorScope(
        color: widget.cursorColor.withValues(alpha: _animation.value),
        cursorWidth: widget.cursorWidth,
        child: inner!,
      ),
      child: child,
    );
  }
}

/// Provides public access to [CursorPainter] for external test use.
///
/// The actual cursor painting is performed by _InlineCursorPainter inside
/// [RichTextRenderer]. This class is retained for API compatibility with
/// existing tests.
class CursorPainter extends CustomPainter {
  /// Creates a [CursorPainter]. Prefer using [RichTextRenderer] with
  /// [cursorColor] for cursor rendering.
  CursorPainter({
    required this.delta,
    required this.cursorOffset,
    this.baseStyle,
    required this.cursorColor,
    required this.cursorWidth,
  });

  /// The inline content used for layout measurement.
  final TextDelta delta;

  /// The character offset at which to draw the caret.
  final int cursorOffset;

  /// The base text style for measurement.
  final TextStyle? baseStyle;

  /// The color of the caret.
  final Color cursorColor;

  /// The width of the caret in logical pixels.
  final double cursorWidth;

  @override
  void paint(Canvas canvas, Size size) {}

  @override
  bool shouldRepaint(CursorPainter old) => false;
}
