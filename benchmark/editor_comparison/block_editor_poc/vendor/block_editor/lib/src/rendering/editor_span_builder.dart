library;

import 'package:flutter/material.dart';
import 'package:block_editor/block_editor.dart';

/// Builds a [TextSpan] tree from [delta] that matches [RichTextRenderer]
/// output exactly — applying per-op inline attributes and resolving
/// [VariableOp] and [TagOp] to their rendered text.
///
/// Used by _resolveOffset and [CursorPainter] so that tap-to-offset
/// resolution and cursor placement both measure against identical text layout.
TextSpan buildMeasurementSpan(
  TextDelta delta,
  TextStyle baseStyle,
  Map<String, String> variables,
) {
  final children = <TextSpan>[];
  for (final op in delta.ops) {
    if (op is TextOp) {
      final attrs = op.attributes;
      Color? color;
      if (attrs.color != null) {
        final hex = attrs.color!.replaceFirst('#', '');
        color = Color(int.parse('FF$hex', radix: 16));
      }
      Color? bgColor;
      if (attrs.backgroundColor != null) {
        final hex = attrs.backgroundColor!.replaceFirst('#', '');
        bgColor = Color(int.parse('FF$hex', radix: 16));
      }
      final isLink = attrs.link != null && attrs.link!.isNotEmpty;
      children.add(
        TextSpan(
          text: op.text,
          style: baseStyle.copyWith(
            fontWeight: attrs.bold == true
                ? FontWeight.bold
                : attrs.bold == false
                ? FontWeight.normal
                : null,
            fontStyle: attrs.italic == true
                ? FontStyle.italic
                : attrs.italic == false
                ? FontStyle.normal
                : null,
            decoration: TextDecoration.combine([
              if (attrs.underline ?? false) TextDecoration.underline,
              if (attrs.strikethrough ?? false) TextDecoration.lineThrough,
            ]),
            fontFamily: (attrs.inlineCode ?? false)
                ? 'monospace'
                : baseStyle.fontFamily,
            color: isLink ? const Color(0xFF0070F3) : color,
            backgroundColor: bgColor,
          ),
        ),
      );
    } else if (op is VariableOp) {
      final resolved = variables[op.variableName] ?? '{{${op.variableName}}}';
      children.add(
        TextSpan(
          text: resolved,
          style: baseStyle.copyWith(color: const Color(0xFF8B5CF6)),
        ),
      );
    } else if (op is TagOp) {
      children.add(
        TextSpan(
          text: '#${op.tag}',
          style: baseStyle.copyWith(color: const Color(0xFF0EA5E9)),
        ),
      );
    }
  }
  return TextSpan(style: baseStyle, children: children);
}

/// Maps a visual character offset in the rendered text back to the
/// corresponding model offset in [delta].
///
/// [TextOp] characters map 1:1. Any visual position within the rendered
/// text of a [VariableOp] or [TagOp] maps to the single model offset
/// immediately after that embed op.
int visualToModelOffset(
  TextDelta delta,
  int visualOffset,
  Map<String, String> variables,
) {
  var modelCursor = 0;
  var visualCursor = 0;
  for (final op in delta.ops) {
    if (op is TextOp) {
      final len = op.text.length;
      if (visualOffset <= visualCursor + len) {
        return modelCursor + (visualOffset - visualCursor);
      }
      visualCursor += len;
      modelCursor += len;
    } else if (op is VariableOp) {
      final resolved = variables[op.variableName] ?? '{{${op.variableName}}}';
      final len = resolved.length;
      if (visualOffset <= visualCursor + len) {
        return modelCursor + 1;
      }
      visualCursor += len;
      modelCursor++;
    } else if (op is TagOp) {
      final rendered = '#${op.tag}';
      final len = rendered.length;
      if (visualOffset <= visualCursor + len) {
        return modelCursor + 1;
      }
      visualCursor += len;
      modelCursor++;
    }
  }
  return modelCursor;
}

/// Maps a model character offset in [delta] forward to the corresponding
/// visual offset in the rendered text.
///
/// [TextOp] characters map 1:1. A model offset pointing at or past a
/// [VariableOp] or [TagOp] advances visual cursor by the full rendered
/// length of that embed.
int modelToVisualOffset(
  TextDelta delta,
  int modelOffset,
  Map<String, String> variables,
) {
  var modelCursor = 0;
  var visualCursor = 0;
  for (final op in delta.ops) {
    if (op is TextOp) {
      final len = op.text.length;
      if (modelOffset <= modelCursor + len) {
        return visualCursor + (modelOffset - modelCursor);
      }
      modelCursor += len;
      visualCursor += len;
    } else if (op is VariableOp) {
      final resolved = variables[op.variableName] ?? '{{${op.variableName}}}';
      if (modelOffset <= modelCursor + 1) {
        return visualCursor + resolved.length;
      }
      modelCursor++;
      visualCursor += resolved.length;
    } else if (op is TagOp) {
      final rendered = '#${op.tag}';
      if (modelOffset <= modelCursor + 1) {
        return visualCursor + rendered.length;
      }
      modelCursor++;
      visualCursor += rendered.length;
    }
  }
  return visualCursor;
}
