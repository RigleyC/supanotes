part of 'delta_operation.dart';

/// Inserts text content.
final class DeltaInsertText extends DeltaOperation {
  /// Creates a text insertion operation.
  DeltaInsertText({
    required String text,
    this.attributes = DeltaAttributes.empty,
  }) : text = _checkNonEmptyString(text, 'text') {
    attributes.requireNoDeletes('insert');
  }

  /// Inserted text.
  final String text;

  /// Formatting attributes applied to [text].
  final DeltaAttributes attributes;

  @override
  int get length => text.length;

  @override
  Map<String, Object?> toJson() => _insertJson(text, attributes);

  @override
  bool operator ==(Object other) {
    return other is DeltaInsertText &&
        text == other.text &&
        attributes == other.attributes;
  }

  @override
  int get hashCode => Object.hash(text, attributes);
}

/// Inserts list content.
final class DeltaInsertListContent extends DeltaOperation {
  /// Creates a list-content insertion operation.
  DeltaInsertListContent(
    Iterable<AnyValue> values, {
    this.attributes = DeltaAttributes.empty,
  }) : values = _checkNonEmptyValues(values) {
    attributes.requireNoDeletes('insert');
  }

  /// Creates list-content insertion from Dart objects.
  factory DeltaInsertListContent.fromObjects(
    Iterable<Object?> values, {
    DeltaAttributes attributes = DeltaAttributes.empty,
  }) {
    return DeltaInsertListContent(
      values.map(AnyValue.fromObject),
      attributes: attributes,
    );
  }

  /// Inserted values.
  final List<AnyValue> values;

  /// Formatting attributes applied to inserted values.
  final DeltaAttributes attributes;

  @override
  int get length => values.length;

  @override
  Map<String, Object?> toJson() {
    return _insertJson(
      List<Object?>.unmodifiable(values.map((value) => value.toObject())),
      attributes,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is DeltaInsertListContent &&
        _listEquals(values, other.values) &&
        attributes == other.attributes;
  }

  @override
  int get hashCode => Object.hash(Object.hashAll(values), attributes);
}

/// Retains existing content, optionally changing formatting attributes.
final class DeltaRetain extends DeltaOperation {
  /// Creates a retain operation.
  DeltaRetain({
    required int length,
    this.attributes = DeltaAttributes.empty,
  }) : length = _checkPositiveLength(length, 'length');

  @override
  final int length;

  /// Formatting changes applied to retained content.
  final DeltaAttributes attributes;

  @override
  Map<String, Object?> toJson() => {
        'retain': length,
        if (attributes.isNotEmpty) 'attributes': attributes.toJson(),
      };

  @override
  bool operator ==(Object other) {
    return other is DeltaRetain &&
        length == other.length &&
        attributes == other.attributes;
  }

  @override
  int get hashCode => Object.hash(length, attributes);
}

/// Deletes existing content.
final class DeltaDelete extends DeltaOperation {
  /// Creates a delete operation.
  DeltaDelete(int length) : length = _checkPositiveLength(length, 'length');

  @override
  final int length;

  @override
  Map<String, Object?> toJson() => {'delete': length};

  @override
  bool operator ==(Object other) {
    return other is DeltaDelete && length == other.length;
  }

  @override
  int get hashCode => length.hashCode;
}

/// Modifies the next child value with nested delta operations.
final class DeltaModifyChild extends DeltaOperation {
  /// Creates a child modification operation.
  DeltaModifyChild({
    required Iterable<DeltaOperation> operations,
    this.attributes = DeltaAttributes.empty,
  }) : operations = _normalizeOperations(operations);

  /// Nested delta operations applied to the child.
  final List<DeltaOperation> operations;

  /// Formatting attributes applied after the nested modification.
  final DeltaAttributes attributes;

  @override
  int get length => 1;

  @override
  Map<String, Object?> toJson() => {
        'modify': _operationsToJson(operations),
        if (attributes.isNotEmpty) 'attributes': attributes.toJson(),
      };

  @override
  bool operator ==(Object other) {
    return other is DeltaModifyChild &&
        _listEquals(operations, other.operations) &&
        attributes == other.attributes;
  }

  @override
  int get hashCode => Object.hash(Object.hashAll(operations), attributes);
}

/// Sets a type-level attribute.
final class DeltaSetAttribute extends DeltaOperation {
  /// Creates a type-level set-attribute operation.
  DeltaSetAttribute({
    required String key,
    required Object? value,
  })  : key = _checkAttributeKey(key),
        value = _jsonValueFromNonNull(value);

  /// Attribute key.
  final String key;

  /// Attribute value.
  final JsonValue value;

  @override
  int get length => 0;

  @override
  bool get isAttributeOperation => true;

  @override
  Map<String, Object?> toJson() => {
        'setAttribute': key,
        'value': value.toObject(),
      };

  @override
  bool operator ==(Object other) {
    return other is DeltaSetAttribute &&
        key == other.key &&
        value == other.value;
  }

  @override
  int get hashCode => Object.hash(key, value);
}

/// Deletes a type-level attribute.
final class DeltaDeleteAttribute extends DeltaOperation {
  /// Creates a type-level delete-attribute operation.
  DeltaDeleteAttribute(String key) : key = _checkAttributeKey(key);

  /// Attribute key.
  final String key;

  @override
  int get length => 0;

  @override
  bool get isAttributeOperation => true;

  @override
  Map<String, Object?> toJson() => {'deleteAttribute': key};

  @override
  bool operator ==(Object other) {
    return other is DeltaDeleteAttribute && key == other.key;
  }

  @override
  int get hashCode => Object.hash(key, null);
}

/// Modifies a type-level nested attribute value.
final class DeltaModifyAttribute extends DeltaOperation {
  /// Creates a type-level modify-attribute operation.
  DeltaModifyAttribute({
    required String key,
    required Iterable<DeltaOperation> operations,
  })  : key = _checkAttributeKey(key),
        operations = _normalizeOperations(operations);

  /// Attribute key.
  final String key;

  /// Nested delta operations applied to the attribute value.
  final List<DeltaOperation> operations;

  @override
  int get length => 0;

  @override
  bool get isAttributeOperation => true;

  @override
  Map<String, Object?> toJson() => {
        'modifyAttribute': key,
        'delta': _operationsToJson(operations),
      };

  @override
  bool operator ==(Object other) {
    return other is DeltaModifyAttribute &&
        key == other.key &&
        _listEquals(operations, other.operations);
  }

  @override
  int get hashCode => Object.hash(key, Object.hashAll(operations));
}

Map<String, Object?> _insertJson(Object? insert, DeltaAttributes attributes) {
  return {
    'insert': insert,
    if (attributes.isNotEmpty) 'attributes': attributes.toJson(),
  };
}

List<AnyValue> _checkNonEmptyValues(Iterable<AnyValue> values) {
  final normalized = List<AnyValue>.unmodifiable(values);
  if (normalized.isEmpty) {
    throw ArgumentError.value(
      normalized,
      'values',
      'must contain at least one value',
    );
  }
  return normalized;
}
