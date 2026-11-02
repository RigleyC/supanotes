library;

import 'package:block_editor/block_editor.dart';
import 'package:flutter/material.dart';

/// Paints a full-width highlight rectangle behind a fully-covered block.
///
/// Used by [BlockSelectionOverlay] when isCovered is true. Blocks that
/// are only partially covered — the start and end blocks of an
/// [ExpandedSelection] — are highlighted inline by [RichTextRenderer] and
/// do not use this painter.
class SelectionHighlightPainter extends CustomPainter {
  /// Creates a [SelectionHighlightPainter] with the given [color].
  const SelectionHighlightPainter({required this.color});

  /// The color of the highlight rectangle.
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 1, size.width, size.height),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(SelectionHighlightPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

/// Wraps a block widget and paints a full-width selection highlight behind
/// it when the block is fully covered by the current selection.
///
/// [isCovered] must be computed by the parent from the current
/// [EditorSelection] and the flattened document order. [BlockSelectionOverlay]
/// is a pure presentation widget — it has no knowledge of document structure.
///
/// Blocks that are partially covered (the anchor or focus block of an
/// [ExpandedSelection]) are highlighted inline by [RichTextRenderer]. This
/// widget handles only fully-covered intermediate blocks.
///
/// When [isCovered] is false the [child] is returned with zero overhead —
/// no extra widget layers are introduced.
class BlockSelectionOverlay extends StatelessWidget {
  /// Creates a [BlockSelectionOverlay] for [child].
  ///
  /// [isCovered] is true when this block falls strictly between the start
  /// and end blocks of an [ExpandedSelection] in document order.
  ///
  /// [highlightColor] defaults to a semi-transparent blue consistent with
  /// the inline highlight color used by [RichTextRenderer].
  const BlockSelectionOverlay({
    super.key,
    required this.child,
    required this.isCovered,
    this.highlightColor = const Color(0x443399FF),
  });

  /// The block widget to wrap.
  final Widget child;

  /// Whether this block is fully covered by the current selection.
  final bool isCovered;

  /// The color of the full-width highlight rectangle.
  final Color highlightColor;

  @override
  Widget build(BuildContext context) {
    if (!isCovered) return child;
    return CustomPaint(
      painter: SelectionHighlightPainter(color: highlightColor),
      child: child,
    );
  }
}
