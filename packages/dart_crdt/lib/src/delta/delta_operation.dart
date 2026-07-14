/// Immutable delta operation value objects.
library;

import '../binary/any_value.dart';
import '../binary/varint_codec.dart';

part 'delta_attributes.dart';
part 'delta_builder.dart';
part 'delta_value.dart';
part 'delta_operation_variants.dart';
part 'attributed_delta.dart';

/// Base class for package-native delta operations.
sealed class DeltaOperation {
  /// Creates a delta operation.
  const DeltaOperation();

  /// Number of visible positions affected by this operation.
  int get length;

  /// Whether this operation targets type-level attributes instead of content.
  bool get isAttributeOperation => false;

  /// Converts this operation to a stable JSON-compatible map.
  Map<String, Object?> toJson();

  /// Stable debug representation used in tests and diagnostics.
  String toDebugString() => toJson().toString();

  @override
  String toString() => toDebugString();
}

int _checkPositiveLength(int length, String name) {
  return RangeError.checkValueInInterval(length, 1, maxSafeInteger, name);
}

String _checkNonEmptyString(String value, String name) {
  if (value.isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty');
  }
  return value;
}

String _checkAttributeKey(String key) {
  return _checkNonEmptyString(key, 'key');
}

JsonValue _jsonValueFromNonNull(Object? value) {
  if (value == null) {
    throw ArgumentError.value(value, 'value', 'use delete for null values');
  }
  return JsonValue.fromObject(value);
}

List<DeltaOperation> _normalizeOperations(Iterable<DeltaOperation> operations) {
  final normalized = List<DeltaOperation>.unmodifiable(operations);
  if (normalized.isEmpty) {
    throw ArgumentError.value(
      normalized,
      'operations',
      'must contain at least one operation',
    );
  }
  return normalized;
}

List<Map<String, Object?>> _operationsToJson(List<DeltaOperation> operations) {
  return List<Map<String, Object?>>.unmodifiable(
    operations.map((operation) => operation.toJson()),
  );
}

bool _listEquals<T>(List<T> left, List<T> right) {
  if (identical(left, right)) {
    return true;
  }
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

int _listHash<T>(Iterable<T> values) => Object.hashAll(values);

bool _stringMapEquals<T>(Map<String, T> left, Map<String, T> right) {
  if (identical(left, right)) {
    return true;
  }
  if (left.length != right.length) {
    return false;
  }
  for (final entry in left.entries) {
    if (!right.containsKey(entry.key) || right[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}

int _stringMapHash<T>(Map<String, T> values) {
  final keys = values.keys.toList()..sort();
  return Object.hashAll(keys.map((key) => Object.hash(key, values[key])));
}
