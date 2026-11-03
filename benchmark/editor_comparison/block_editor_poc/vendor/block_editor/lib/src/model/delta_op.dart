library;

import 'package:meta/meta.dart';

import 'inline_attributes.dart';
import 'text_delta.dart';

/// The base type for all operations in a [TextDelta].
///
/// Every op is immutable. The sealed class guarantees exhaustive switching
/// across all subtypes at compile time.
@immutable
sealed class DeltaOp {
  const DeltaOp();

  /// Deserializes a [DeltaOp] from a JSON-compatible map.
  ///
  /// Throws [FormatException] for unknown type strings.
  factory DeltaOp.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    return switch (type) {
      'text' => TextOp.fromJson(json),
      'variable' => VariableOp.fromJson(json),
      'tag' => TagOp.fromJson(json),
      _ => throw FormatException('Unknown DeltaOp type: $type', json),
    };
  }

  /// Serializes this op to a JSON-compatible map.
  Map<String, dynamic> toJson();
}

/// A run of plain or formatted text within a [TextDelta].
@immutable
final class TextOp extends DeltaOp {
  /// Creates a [TextOp] with [text] and optional [attributes].
  const TextOp(this.text, {InlineAttributes? attributes})
    : attributes = attributes ?? const InlineAttributes();

  /// Deserializes a [TextOp] from [json].
  factory TextOp.fromJson(Map<String, dynamic> json) {
    return TextOp(
      json['text'] as String,
      attributes: json['attributes'] != null
          ? InlineAttributes.fromJson(
              json['attributes'] as Map<String, dynamic>,
            )
          : null,
    );
  }

  /// The text content of this op.
  final String text;

  /// The inline formatting attributes applied to [text].
  final InlineAttributes attributes;

  /// Returns a copy of this op with the given fields replaced.
  TextOp copyWith({String? text, InlineAttributes? attributes}) {
    return TextOp(text ?? this.text, attributes: attributes ?? this.attributes);
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': 'text',
      'text': text,
      if (!attributes.isEmpty) 'attributes': attributes.toJson(),
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TextOp &&
        other.text == text &&
        other.attributes == attributes;
  }

  @override
  int get hashCode => Object.hash(text, attributes);

  @override
  String toString() => 'TextOp("$text", $attributes)';
}

/// An inline variable embed within a [TextDelta].
///
/// [VariableOp] stores a variable name that is resolved at render time
/// against a [Map<String, String>] supplied externally. The document is
/// never modified during resolution — the variable name is always stored
/// verbatim and the resolved value only ever appears in the rendered output.
@immutable
final class VariableOp extends DeltaOp {
  /// Creates a [VariableOp] for the variable identified by [variableName].
  const VariableOp(this.variableName);

  /// Deserializes a [VariableOp] from [json].
  factory VariableOp.fromJson(Map<String, dynamic> json) {
    return VariableOp(json['variableName'] as String);
  }

  /// The name of the variable to resolve at render time.
  final String variableName;

  @override
  Map<String, dynamic> toJson() {
    return {'type': 'variable', 'variableName': variableName};
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is VariableOp && other.variableName == variableName;
  }

  @override
  int get hashCode => variableName.hashCode;

  @override
  String toString() => 'VariableOp("$variableName")';
}

/// An inline tag embed within a [TextDelta].
///
/// [TagOp] stores a tag string that is queryable via
/// BlockController.tags. Tags are always stored verbatim in the document
/// and rendered as-is with a leading `#` prefix.
@immutable
final class TagOp extends DeltaOp {
  /// Creates a [TagOp] for [tag].
  const TagOp(this.tag);

  /// Deserializes a [TagOp] from [json].
  factory TagOp.fromJson(Map<String, dynamic> json) {
    return TagOp(json['tag'] as String);
  }

  /// The tag string, stored without the leading `#`.
  final String tag;

  @override
  Map<String, dynamic> toJson() {
    return {'type': 'tag', 'tag': tag};
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TagOp && other.tag == tag;
  }

  @override
  int get hashCode => tag.hashCode;

  @override
  String toString() => 'TagOp("$tag")';
}
