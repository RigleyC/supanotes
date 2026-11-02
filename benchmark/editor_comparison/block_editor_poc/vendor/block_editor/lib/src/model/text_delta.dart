library;

import 'package:meta/meta.dart';

import 'delta_op.dart';
import 'inline_attributes.dart';

@immutable
final class TextDelta {
  TextDelta(List<DeltaOp> ops) : ops = _normalize(ops);

  TextDelta.empty() : ops = const [];

  TextDelta.fromPlainText(String text)
    : ops = text.isEmpty ? const [] : [TextOp(text)];

  factory TextDelta.fromJson(List<dynamic> json) {
    final ops = json
        .map((e) => DeltaOp.fromJson(e as Map<String, dynamic>))
        .toList();
    return TextDelta(_normalize(ops));
  }

  final List<DeltaOp> ops;

  /// Returns the plain-text representation of this delta.
  ///
  /// Each [TextOp] contributes its text verbatim. Each [VariableOp] and
  /// [TagOp] contributes a single Unicode object-replacement character
  /// `'\uFFFC'`, so that every embed op counts as exactly one logical
  /// character in all offset calculations. This keeps the model-layer offset
  /// system consistent with the render layer regardless of how many visible
  /// characters an embed renders as.
  String get plainText {
    final buffer = StringBuffer();
    for (final op in ops) {
      if (op is TextOp) {
        buffer.write(op.text);
      } else if (op is VariableOp || op is TagOp) {
        buffer.write('\uFFFC');
      }
    }
    return buffer.toString();
  }

  bool get isEmpty => ops.isEmpty;
  bool get isNotEmpty => ops.isNotEmpty;

  TextDelta append(DeltaOp op) => TextDelta(_normalize([...ops, op]));

  TextDelta concat(TextDelta other) =>
      TextDelta(_normalize([...ops, ...other.ops]));

  TextDelta applyAttributes(int start, int end, InlineAttributes attributes) {
    assert(start >= 0 && end >= start, 'Invalid range [$start, $end)');

    final allBold =
        attributes.bold != null && _allHave(start, end, (a) => a.bold == true);
    final allItalic =
        attributes.italic != null &&
        _allHave(start, end, (a) => a.italic == true);
    final allUnderline =
        attributes.underline != null &&
        _allHave(start, end, (a) => a.underline == true);
    final allStrikethrough =
        attributes.strikethrough != null &&
        _allHave(start, end, (a) => a.strikethrough == true);
    final allInlineCode =
        attributes.inlineCode != null &&
        _allHave(start, end, (a) => a.inlineCode == true);

    final result = <DeltaOp>[];
    var cursor = 0;

    for (final op in ops) {
      if (op is! TextOp) {
        result.add(op);
        cursor++;
        continue;
      }
      final opStart = cursor;
      final opEnd = cursor + op.text.length;
      cursor = opEnd;

      if (opEnd <= start || opStart >= end) {
        result.add(op);
        continue;
      }

      final before = op.text.substring(
        0,
        (start - opStart).clamp(0, op.text.length),
      );
      final inside = op.text.substring(
        (start - opStart).clamp(0, op.text.length),
        (end - opStart).clamp(0, op.text.length),
      );
      final after = op.text.substring((end - opStart).clamp(0, op.text.length));

      if (before.isNotEmpty) {
        result.add(TextOp(before, attributes: op.attributes));
      }
      if (inside.isNotEmpty) {
        final a = op.attributes;
        result.add(
          TextOp(
            inside,
            attributes: InlineAttributes(
              bold: attributes.bold != null ? (allBold ? null : true) : a.bold,
              italic: attributes.italic != null
                  ? (allItalic ? null : true)
                  : a.italic,
              underline: attributes.underline != null
                  ? (allUnderline ? null : true)
                  : a.underline,
              strikethrough: attributes.strikethrough != null
                  ? (allStrikethrough ? null : true)
                  : a.strikethrough,
              inlineCode: attributes.inlineCode != null
                  ? (allInlineCode ? null : true)
                  : a.inlineCode,
              link: attributes.link ?? a.link,
              color: attributes.color ?? a.color,
              backgroundColor: attributes.backgroundColor ?? a.backgroundColor,
            ),
          ),
        );
      }
      if (after.isNotEmpty) {
        result.add(TextOp(after, attributes: op.attributes));
      }
    }

    return TextDelta(_normalize(result));
  }

  bool _allHave(int start, int end, bool Function(InlineAttributes) test) {
    var cursor = 0;
    var foundAny = false;
    for (final op in ops) {
      if (op is! TextOp) {
        cursor++;
        continue;
      }
      final opStart = cursor;
      final opEnd = cursor + op.text.length;
      cursor = opEnd;
      if (opEnd <= start || opStart >= end) continue;
      foundAny = true;
      if (!test(op.attributes)) return false;
    }
    return foundAny;
  }

  TextDelta slice(int start, int end) {
    assert(start >= 0 && end >= start, 'Invalid range [$start, $end)');
    final result = <DeltaOp>[];
    var cursor = 0;

    for (final op in ops) {
      if (op is! TextOp) {
        if (cursor >= start && cursor < end) result.add(op);
        cursor++;
        continue;
      }
      final opStart = cursor;
      final opEnd = cursor + op.text.length;
      cursor = opEnd;

      if (opEnd <= start || opStart >= end) continue;

      final sliceStart = (start - opStart).clamp(0, op.text.length);
      final sliceEnd = (end - opStart).clamp(0, op.text.length);
      result.add(
        TextOp(
          op.text.substring(sliceStart, sliceEnd),
          attributes: op.attributes,
        ),
      );
    }

    return TextDelta(_normalize(result));
  }

  List<Map<String, dynamic>> toJson() => ops.map((op) => op.toJson()).toList();

  static List<DeltaOp> _normalize(List<DeltaOp> ops) {
    final result = <DeltaOp>[];
    for (final op in ops) {
      if (op is TextOp && op.text.isEmpty) continue;
      if (result.isNotEmpty && result.last is TextOp && op is TextOp) {
        final prev = result.last as TextOp;
        if (prev.attributes == op.attributes) {
          result[result.length - 1] = TextOp(
            prev.text + op.text,
            attributes: prev.attributes,
          );
          continue;
        }
      }
      result.add(op);
    }
    return List.unmodifiable(result);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! TextDelta || other.ops.length != ops.length) return false;
    for (var i = 0; i < ops.length; i++) {
      if (ops[i] != other.ops[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(ops);

  @override
  String toString() => 'TextDelta(${ops.length} ops: "$plainText")';
}
