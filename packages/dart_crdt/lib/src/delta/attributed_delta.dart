part of 'delta_operation.dart';

/// Attribution metadata attached to rendered delta operations.
final class DeltaAttribution {
  /// Creates attribution metadata.
  DeltaAttribution({
    required String key,
    required Object? value,
  })  : key = _checkAttributeKey(key),
        value = _jsonValueFromNonNull(value);

  /// Attribution key.
  final String key;

  /// Attribution value.
  final JsonValue value;

  /// Converts this attribution to stable JSON.
  Map<String, Object?> toJson() => {
        'key': key,
        'value': value.toObject(),
      };

  @override
  bool operator ==(Object other) {
    return other is DeltaAttribution &&
        key == other.key &&
        value == other.value;
  }

  @override
  int get hashCode => Object.hash(key, value);
}

/// Immutable completed delta plus rendered attribution groups.
final class AttributedDelta {
  /// Creates an attributed delta.
  AttributedDelta({
    required this.delta,
    Iterable<DeltaAttribution> insertions = const <DeltaAttribution>[],
    Iterable<DeltaAttribution> deletions = const <DeltaAttribution>[],
    Iterable<DeltaAttribution> formatting = const <DeltaAttribution>[],
  })  : insertions = List<DeltaAttribution>.unmodifiable(insertions),
        deletions = List<DeltaAttribution>.unmodifiable(deletions),
        formatting = List<DeltaAttribution>.unmodifiable(formatting);

  /// Completed rendered delta.
  final Delta delta;

  /// Attribution metadata for insertions.
  final List<DeltaAttribution> insertions;

  /// Attribution metadata for deletions.
  final List<DeltaAttribution> deletions;

  /// Attribution metadata for formatting changes.
  final List<DeltaAttribution> formatting;

  /// Whether no attribution metadata is present.
  bool get isUnattributed {
    return insertions.isEmpty && deletions.isEmpty && formatting.isEmpty;
  }

  /// Converts this attributed delta to stable JSON.
  Map<String, Object?> toJson() => {
        'delta': delta.toJson(),
        if (insertions.isNotEmpty)
          'insertions': _attributionsToJson(insertions),
        if (deletions.isNotEmpty) 'deletions': _attributionsToJson(deletions),
        if (formatting.isNotEmpty)
          'formatting': _attributionsToJson(formatting),
      };

  @override
  bool operator ==(Object other) {
    return other is AttributedDelta &&
        delta == other.delta &&
        _listEquals(insertions, other.insertions) &&
        _listEquals(deletions, other.deletions) &&
        _listEquals(formatting, other.formatting);
  }

  @override
  int get hashCode {
    return Object.hash(
      delta,
      Object.hashAll(insertions),
      Object.hashAll(deletions),
      Object.hashAll(formatting),
    );
  }

  @override
  String toString() => toJson().toString();
}

List<Map<String, Object?>> _attributionsToJson(
  List<DeltaAttribution> attributions,
) {
  return List<Map<String, Object?>>.unmodifiable(
    attributions.map((attribution) => attribution.toJson()),
  );
}
