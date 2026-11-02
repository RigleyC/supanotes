library;

import 'package:flutter/material.dart';
import 'package:block_editor/block_editor.dart';
import 'editor_span_builder.dart';

/// Converts a [TextDelta] into an inline-styled [Text.rich] widget.
///
/// When [CursorColorScope] is present and [selection] is a [CollapsedSelection]
/// for [blockId], a blinking caret is painted. The caret uses the actual
/// rendered width of the [Text.rich] widget — obtained via a [GlobalKey] after
/// layout — so the [TextPainter] measurement wraps identically to the rendered
/// text regardless of how parent widgets constrain the editor.
class RichTextRenderer extends StatelessWidget {
  /// Creates a [RichTextRenderer] for [delta].
  const RichTextRenderer({
    super.key,
    required this.delta,
    required this.blockId,
    this.baseStyle,
    this.selection = EditorSelection.none,
    this.selectionColor = const Color(0x443399FF),
    this.inlineCodeColor = const Color(0xFFEEEEEE),
    this.textAlign = TextAlign.start,
    this.composingRange,
    this.cursorColor,
    this.cursorWidth = 2.0,
  });

  /// The content to render.
  final TextDelta delta;

  /// The id of the block this renderer belongs to.
  final String blockId;

  /// The base [TextStyle] inherited by all spans.
  final TextStyle? baseStyle;

  /// The current editor selection, used to paint inline highlights.
  final EditorSelection selection;

  /// Background color applied to selected character ranges.
  final Color selectionColor;

  /// Background color applied to inline code runs.
  final Color inlineCodeColor;

  /// How the text should be aligned horizontally.
  final TextAlign textAlign;

  /// The active IME composing region, or null when no composition is active.
  final TextRange? composingRange;

  /// When non-null and [selection] is a [CollapsedSelection] for [blockId],
  /// a blinking caret is painted at the cursor position with this color.
  final Color? cursorColor;

  /// The width of the caret in logical pixels.
  final double cursorWidth;

  @override
  Widget build(BuildContext context) {
    final variables = BlockEditorScope.maybeOf(context)?.variables ?? const {};
    final spans = _buildSpans(variables);
    final textWidget = Text.rich(
      TextSpan(style: baseStyle, children: spans),
      textAlign: textAlign,
      semanticsLabel: delta.plainText,
      textHeightBehavior: const TextHeightBehavior(
        applyHeightToFirstAscent: false,
        applyHeightToLastDescent: false,
      ),
    );

    final sel = selection;
    final isCursorBlock =
        sel is CollapsedSelection &&
        sel.point.blockId == blockId &&
        sel.point.offset >= 0;

    if (!isCursorBlock) return textWidget;

    final scope = CursorColorScope.maybeOf(context);
    final activeCursorColor = cursorColor ?? scope?.color;
    if (activeCursorColor == null) return textWidget;

    final effectiveBase = baseStyle ?? const TextStyle(fontSize: 16);
    final effectiveCursorWidth = (scope?.cursorWidth ?? cursorWidth) - 1.0;
    final cursorOff = (sel).point.offset;

    return LayoutBuilder(
      builder: (context, constraints) {
        final textWidth = constraints.maxWidth;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            textWidget,
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _InlineCursorPainter(
                    delta: delta,
                    baseStyle: effectiveBase,
                    variables: variables,
                    cursorOffset: cursorOff,
                    cursorColor: activeCursorColor,
                    cursorWidth: effectiveCursorWidth,
                    textWidth: textWidth,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  List<TextSpan> _buildSpans(Map<String, String> variables) {
    final spans = <TextSpan>[];
    var offset = 0;

    final selRange = _resolvedSelectionRange();

    for (final op in delta.ops) {
      if (op is VariableOp) {
        final resolved = variables[op.variableName] ?? '{{${op.variableName}}}';
        final opStart = offset;
        final opEnd = offset + 1;
        final highlight =
            selRange != null && opStart >= selRange.$1 && opEnd <= selRange.$2
            ? selectionColor
            : null;
        spans.add(
          TextSpan(
            text: resolved,
            style: TextStyle(
              color: const Color(0xFF8B5CF6),
              backgroundColor: highlight,
            ),
          ),
        );
        offset += 1;
        continue;
      }
      if (op is TagOp) {
        final opStart = offset;
        final opEnd = offset + 1;
        final highlight =
            selRange != null && opStart >= selRange.$1 && opEnd <= selRange.$2
            ? selectionColor
            : null;
        spans.add(
          TextSpan(
            text: '#${op.tag}',
            style: TextStyle(
              color: const Color(0xFF0EA5E9),
              backgroundColor: highlight,
            ),
          ),
        );
        offset += 1;
        continue;
      }
      if (op is! TextOp) {
        offset++;
        continue;
      }
      final length = op.text.length;
      final opStart = offset;
      final opEnd = offset + length;
      if (composingRange != null &&
          _overlaps(opStart, opEnd, composingRange!)) {
        spans.addAll(_buildSpansWithComposing(op, opStart, opEnd));
      } else if (selRange != null &&
          _overlaps(
            opStart,
            opEnd,
            TextRange(start: selRange.$1, end: selRange.$2),
          )) {
        spans.addAll(
          _buildSpansWithSelection(
            op,
            opStart,
            opEnd,
            selRange.$1,
            selRange.$2,
          ),
        );
      } else {
        spans.add(_buildSpan(op, opStart, opEnd));
      }
      offset = opEnd;
    }
    return spans;
  }

  (int, int)? _resolvedSelectionRange() {
    final sel = selection;
    if (sel is! ExpandedSelection) return null;
    final anchorId = sel.anchor.blockId;
    final focusId = sel.focus.blockId;
    if (anchorId == focusId) {
      if (blockId != anchorId) return null;
      final s = sel.anchor.offset <= sel.focus.offset
          ? sel.anchor.offset
          : sel.focus.offset;
      final e = sel.anchor.offset <= sel.focus.offset
          ? sel.focus.offset
          : sel.anchor.offset;
      return (s, e);
    }
    if (blockId == anchorId) {
      return (sel.anchor.offset, delta.plainText.length);
    }
    if (blockId == focusId) {
      return (0, sel.focus.offset);
    }
    if (blockId != anchorId && blockId != focusId) {
      return (0, delta.plainText.length);
    }
    return null;
  }

  List<TextSpan> _buildSpansWithSelection(
    TextOp op,
    int opStart,
    int opEnd,
    int selStart,
    int selEnd,
  ) {
    final result = <TextSpan>[];
    final clipStart = selStart.clamp(opStart, opEnd);
    final clipEnd = selEnd.clamp(opStart, opEnd);
    if (clipStart > opStart) {
      result.add(
        _buildSpan(
          TextOp(
            op.text.substring(0, clipStart - opStart),
            attributes: op.attributes,
          ),
          opStart,
          clipStart,
        ),
      );
    }
    if (clipEnd > clipStart) {
      final selected = TextOp(
        op.text.substring(clipStart - opStart, clipEnd - opStart),
        attributes: op.attributes,
      );
      var style = _spanStyle(selected);
      style = style.copyWith(backgroundColor: selectionColor);
      result.add(TextSpan(text: selected.text, style: style));
    }
    if (clipEnd < opEnd) {
      result.add(
        _buildSpan(
          TextOp(
            op.text.substring(clipEnd - opStart),
            attributes: op.attributes,
          ),
          clipEnd,
          opEnd,
        ),
      );
    }
    return result;
  }

  TextStyle _spanStyle(TextOp op) {
    final attrs = op.attributes;
    final isCode = attrs.inlineCode ?? false;
    final isLink = attrs.link != null;
    return TextStyle(
      fontWeight: (attrs.bold ?? false) ? FontWeight.bold : null,
      fontStyle: (attrs.italic ?? false) ? FontStyle.italic : null,
      decoration: _buildDecoration(attrs),
      fontFamily: isCode ? 'monospace' : null,
      backgroundColor: _resolveBackgroundColor(attrs),
      color: _resolveColor(attrs, isLink),
    );
  }

  bool _overlaps(int opStart, int opEnd, TextRange range) =>
      opStart < range.end && opEnd > range.start;

  List<TextSpan> _buildSpansWithComposing(TextOp op, int opStart, int opEnd) {
    final range = composingRange!;
    final compStart = range.start.clamp(opStart, opEnd);
    final compEnd = range.end.clamp(opStart, opEnd);
    final result = <TextSpan>[];
    if (compStart > opStart) {
      result.add(
        _buildSpan(
          TextOp(
            op.text.substring(0, compStart - opStart),
            attributes: op.attributes,
          ),
          opStart,
          compStart,
        ),
      );
    }
    if (compEnd > compStart) {
      result.add(
        _buildSpanWithComposingUnderline(
          TextOp(
            op.text.substring(compStart - opStart, compEnd - opStart),
            attributes: op.attributes,
          ),
          compStart,
          compEnd,
        ),
      );
    }
    if (compEnd < opEnd) {
      result.add(
        _buildSpan(
          TextOp(
            op.text.substring(compEnd - opStart),
            attributes: op.attributes,
          ),
          compEnd,
          opEnd,
        ),
      );
    }
    return result;
  }

  TextSpan _buildSpanWithComposingUnderline(TextOp op, int start, int end) {
    final attrs = op.attributes;
    final isCode = attrs.inlineCode ?? false;
    final isLink = attrs.link != null;
    final decorations = <TextDecoration>[TextDecoration.underline];
    if (attrs.underline ?? false) decorations.add(TextDecoration.underline);
    if (attrs.strikethrough ?? false) {
      decorations.add(TextDecoration.lineThrough);
    }
    final style = TextStyle(
      fontWeight: (attrs.bold ?? false) ? FontWeight.bold : null,
      fontStyle: (attrs.italic ?? false) ? FontStyle.italic : null,
      decoration: TextDecoration.combine(decorations),
      fontFamily: isCode ? 'monospace' : null,
      backgroundColor: _resolveBackgroundColor(attrs),
      color: _resolveColor(attrs, isLink),
    );
    return TextSpan(text: op.text, style: style);
  }

  TextSpan _buildSpan(TextOp op, int start, int end) {
    final attrs = op.attributes;
    final isCode = attrs.inlineCode ?? false;
    final isLink = attrs.link != null;
    final style = TextStyle(
      fontWeight: (attrs.bold ?? false) ? FontWeight.bold : null,
      fontStyle: (attrs.italic ?? false) ? FontStyle.italic : null,
      decoration: _buildDecoration(attrs),
      fontFamily: isCode ? 'monospace' : null,
      backgroundColor: _resolveBackgroundColor(attrs),
      color: _resolveColor(attrs, isLink),
    );
    return TextSpan(text: op.text, style: style);
  }

  TextDecoration? _buildDecoration(InlineAttributes attrs) {
    final d = <TextDecoration>[];
    if (attrs.underline ?? false) d.add(TextDecoration.underline);
    if (attrs.strikethrough ?? false) d.add(TextDecoration.lineThrough);
    if (d.isEmpty) return null;
    return TextDecoration.combine(d);
  }

  Color? _resolveColor(InlineAttributes attrs, bool isLink) {
    if (attrs.color != null) {
      return Color(int.parse(attrs.color!.replaceFirst('#', '0xFF')));
    }
    if (isLink) return const Color(0xFF0070F3);
    return null;
  }

  Color? _resolveBackgroundColor(InlineAttributes attrs) {
    final isCode = attrs.inlineCode ?? false;
    if (isCode) return inlineCodeColor;
    if (attrs.backgroundColor != null) {
      return Color(int.parse(attrs.backgroundColor!.replaceFirst('#', '0xFF')));
    }
    return null;
  }
}

class _InlineCursorPainter extends CustomPainter {
  _InlineCursorPainter({
    required this.delta,
    required this.baseStyle,
    required this.variables,
    required this.cursorOffset,
    required this.cursorColor,
    required this.cursorWidth,
    required this.textWidth,
  });

  final TextDelta delta;
  final TextStyle baseStyle;
  final Map<String, String> variables;
  final int cursorOffset;
  final Color cursorColor;
  final double cursorWidth;
  final double textWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (cursorOffset < 0) return;

    final span = buildMeasurementSpan(delta, baseStyle, variables);
    final painter = TextPainter(
      text: span,
      textDirection: TextDirection.ltr,
      textHeightBehavior: const TextHeightBehavior(
        applyHeightToFirstAscent: false,
        applyHeightToLastDescent: false,
      ),
    )..layout(maxWidth: textWidth);

    final visualOffset = modelToVisualOffset(delta, cursorOffset, variables);
    final plainVisualLength = span.toPlainText().length;
    final clampedOffset = visualOffset.clamp(0, plainVisualLength);

    final caretOffset = painter.getOffsetForCaret(
      TextPosition(offset: clampedOffset),
      Rect.zero,
    );

    final lineMetrics = painter.computeLineMetrics();
    double lineHeight = painter.preferredLineHeight;
    for (final m in lineMetrics) {
      final mTop = m.baseline - m.ascent;
      if (caretOffset.dy >= mTop - 1.0 && caretOffset.dy < mTop + m.height) {
        lineHeight = m.ascent + m.descent;
        break;
      }
    }

    final scale = painter.height > 0 ? size.height / painter.height : 1.0;
    final cursorTop = caretOffset.dy * scale;
    final scaledLineHeight = lineHeight * scale;

    canvas.drawRect(
      Rect.fromLTWH(caretOffset.dx, cursorTop, cursorWidth, scaledLineHeight),
      Paint()
        ..color = cursorColor
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(_InlineCursorPainter old) =>
      old.cursorOffset != cursorOffset ||
      old.cursorColor != cursorColor ||
      old.delta != delta ||
      old.textWidth != textWidth;
}
