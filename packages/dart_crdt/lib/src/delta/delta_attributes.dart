part of 'delta_operation.dart';

/// Formatting attributes attached to content operations.
final class DeltaAttributes {
  /// Creates normalized attributes from [changes].
  factory DeltaAttributes(Iterable<DeltaAttributeChange> changes) {
    final byKey = <String, DeltaAttributeChange>{};
    for (final change in changes) {
      if (byKey.containsKey(change.key)) {
        throw ArgumentError.value(change.key, 'changes', 'duplicate key');
      }
      byKey[change.key] = change;
    }
    final sortedKeys = byKey.keys.toList()..sort();
    return DeltaAttributes._({
      for (final key in sortedKeys) key: byKey[key]!,
    });
  }

  /// Creates formatting attributes from a JSON-compatible map.
  factory DeltaAttributes.fromJson(Map<String, Object?> attributes) {
    return DeltaAttributes(
      attributes.entries.map((entry) {
        final value = entry.value;
        if (value == null) {
          return DeltaAttributeDelete(entry.key);
        }
        return DeltaAttributeSet(key: entry.key, value: value);
      }),
    );
  }

  const DeltaAttributes._(this._changes);

  /// Empty formatting attributes.
  static const empty = DeltaAttributes._(<String, DeltaAttributeChange>{});

  final Map<String, DeltaAttributeChange> _changes;

  /// Attribute changes sorted by key.
  List<DeltaAttributeChange> get changes {
    return List<DeltaAttributeChange>.unmodifiable(_changes.values);
  }

  /// Whether no attributes are present.
  bool get isEmpty => _changes.isEmpty;

  /// Whether at least one attribute is present.
  bool get isNotEmpty => _changes.isNotEmpty;

  /// Whether any attribute removes formatting using null-as-remove semantics.
  bool get hasDeletes {
    return _changes.values.any((change) => change is DeltaAttributeDelete);
  }

  /// Returns the change for [key], or `null` when absent.
  DeltaAttributeChange? operator [](String key) => _changes[key];

  /// Throws if this attribute set contains removals.
  void requireNoDeletes(String operationName) {
    if (!hasDeletes) {
      return;
    }
    throw ArgumentError.value(
      toJson(),
      'attributes',
      '$operationName attributes cannot remove formatting',
    );
  }

  /// Converts attributes to a stable JSON-compatible map.
  Map<String, Object?> toJson() {
    return Map<String, Object?>.unmodifiable({
      for (final entry in _changes.entries)
        entry.key: entry.value.toJsonValue(),
    });
  }

  @override
  bool operator ==(Object other) {
    return other is DeltaAttributes &&
        _stringMapEquals(_changes, other._changes);
  }

  @override
  int get hashCode => _stringMapHash(_changes);

  @override
  String toString() => toJson().toString();
}

/// A single formatting attribute change.
sealed class DeltaAttributeChange {
  /// Creates an attribute change with a validated [key].
  DeltaAttributeChange(String key) : key = _checkAttributeKey(key);

  /// Attribute key.
  final String key;

  /// JSON-compatible value for this change.
  Object? toJsonValue();
}

/// Sets a formatting attribute to a JSON value.
final class DeltaAttributeSet extends DeltaAttributeChange {
  /// Creates a set-attribute change.
  DeltaAttributeSet({
    required String key,
    required Object? value,
  })  : value = _jsonValueFromNonNull(value),
        super(key);

  /// JSON value assigned to [key].
  final JsonValue value;

  @override
  Object? toJsonValue() => value.toObject();

  @override
  bool operator ==(Object other) {
    return other is DeltaAttributeSet &&
        key == other.key &&
        value == other.value;
  }

  @override
  int get hashCode => Object.hash(key, value);
}

/// Removes a formatting attribute.
final class DeltaAttributeDelete extends DeltaAttributeChange {
  /// Creates a delete-attribute change.
  DeltaAttributeDelete(super.key);

  @override
  Object? toJsonValue() => null;

  @override
  bool operator ==(Object other) {
    return other is DeltaAttributeDelete && key == other.key;
  }

  @override
  int get hashCode => Object.hash(key, null);
}

/// Modifies a nested attribute value with child delta operations.
final class DeltaAttributeModify extends DeltaAttributeChange {
  /// Creates a modify-attribute change.
  DeltaAttributeModify({
    required String key,
    required Iterable<DeltaOperation> operations,
  })  : operations = _normalizeOperations(operations),
        super(key);

  /// Nested delta operations.
  final List<DeltaOperation> operations;

  @override
  Object? toJsonValue() => <String, Object?>{
        'ops': _operationsToJson(operations),
      };

  @override
  bool operator ==(Object other) {
    return other is DeltaAttributeModify &&
        key == other.key &&
        _listEquals(operations, other.operations);
  }

  @override
  int get hashCode => Object.hash(key, Object.hashAll(operations));
}
