/// Typed JSON-compatible and binary-capable value objects.
library;

import 'dart:typed_data';

part 'any_container_value.dart';

/// Thrown when an object cannot be converted to an [AnyValue].
final class UnsupportedAnyValueException implements Exception {
  /// Creates an exception for [value] with an explanatory [reason].
  const UnsupportedAnyValueException({
    required this.value,
    required this.reason,
  });

  /// The unsupported source value.
  final Object? value;

  /// The reason the value is unsupported.
  final String reason;

  /// A human-readable description of the unsupported value.
  String get message => 'Unsupported value "$value": $reason.';

  @override
  String toString() => 'UnsupportedAnyValueException: $message';
}

/// A value that can be encoded by the binary any-value codec.
sealed class AnyValue {
  /// Creates an any-value instance.
  const AnyValue();

  /// Converts a Dart object into an [AnyValue].
  factory AnyValue.fromObject(Object? value) => _anyFromObject(value);

  /// Converts this value to a defensive Dart object representation.
  Object? toObject();
}

/// A JSON-compatible value without binary payloads.
sealed class JsonValue extends AnyValue {
  /// Creates a JSON value instance.
  const JsonValue();

  /// Converts a Dart JSON object into a [JsonValue].
  factory JsonValue.fromObject(Object? value) => _jsonFromObject(value);
}

/// A JSON null value.
final class JsonNull extends JsonValue {
  /// Creates a JSON null value.
  const JsonNull();

  @override
  Object? toObject() => null;

  @override
  bool operator ==(Object other) => other is JsonNull;

  @override
  int get hashCode => 0;
}

/// A JSON boolean value.
final class JsonBool extends JsonValue {
  /// Creates a JSON boolean value.
  const JsonBool(this.value);

  /// The boolean payload.
  final bool value;

  @override
  bool toObject() => value;

  @override
  bool operator ==(Object other) => other is JsonBool && value == other.value;

  @override
  int get hashCode => value.hashCode;
}

/// A finite JSON number value.
final class JsonNumber extends JsonValue {
  /// Creates a JSON number value.
  JsonNumber(this.value) {
    if (!value.isFinite) {
      throw UnsupportedAnyValueException(
        value: value,
        reason: 'JSON numbers must be finite',
      );
    }
  }

  /// The numeric payload.
  final num value;

  @override
  num toObject() => value;

  @override
  bool operator ==(Object other) => other is JsonNumber && value == other.value;

  @override
  int get hashCode => value.hashCode;
}

/// A JSON string value.
final class JsonString extends JsonValue {
  /// Creates a JSON string value.
  const JsonString(this.value);

  /// The string payload.
  final String value;

  @override
  String toObject() => value;

  @override
  bool operator ==(Object other) => other is JsonString && value == other.value;

  @override
  int get hashCode => value.hashCode;
}

/// A JSON array value.
final class JsonList extends JsonValue {
  /// Creates a JSON array value with a defensive copy of [values].
  JsonList(Iterable<JsonValue> values) : values = List.unmodifiable(values);

  /// The array elements.
  final List<JsonValue> values;

  @override
  List<Object?> toObject() => List<Object?>.unmodifiable(
        values.map((value) => value.toObject()),
      );

  @override
  bool operator ==(Object other) =>
      other is JsonList && _listEquals(values, other.values);

  @override
  int get hashCode => _listHash(values);
}

/// A JSON object value.
final class JsonMap extends JsonValue {
  /// Creates a JSON object value with a defensive copy of [entries].
  JsonMap(Map<String, JsonValue> entries) : entries = Map.unmodifiable(entries);

  /// The object entries.
  final Map<String, JsonValue> entries;

  @override
  Map<String, Object?> toObject() => Map<String, Object?>.unmodifiable(
        entries.map((key, value) => MapEntry(key, value.toObject())),
      );

  @override
  bool operator ==(Object other) =>
      other is JsonMap && _stringMapEquals(entries, other.entries);

  @override
  int get hashCode => _stringMapHash(entries);
}

AnyValue _anyFromObject(Object? value) {
  if (value is Uint8List) {
    return AnyBinary(value);
  }
  if (value is List<Object?>) {
    return AnyList(value.map(AnyValue.fromObject));
  }
  if (value is Map<Object?, Object?>) {
    return AnyMap(_mapAnyEntries(value));
  }
  return _jsonFromObject(value);
}

JsonValue _jsonFromObject(Object? value) {
  if (value == null) {
    return const JsonNull();
  }
  if (value is bool) {
    return JsonBool(value);
  }
  if (value is num) {
    return JsonNumber(value);
  }
  if (value is String) {
    return JsonString(value);
  }
  if (value is List<Object?>) {
    return JsonList(value.map(JsonValue.fromObject));
  }
  if (value is Map<Object?, Object?>) {
    return JsonMap(_mapJsonEntries(value));
  }
  throw UnsupportedAnyValueException(
    value: value,
    reason: 'expected null, bool, number, string, list, map, or Uint8List',
  );
}

Map<String, AnyValue> _mapAnyEntries(Map<Object?, Object?> source) {
  return {
    for (final entry in source.entries)
      _requireStringKey(entry.key): AnyValue.fromObject(entry.value),
  };
}

Map<String, JsonValue> _mapJsonEntries(Map<Object?, Object?> source) {
  return {
    for (final entry in source.entries)
      _requireStringKey(entry.key): JsonValue.fromObject(entry.value),
  };
}

String _requireStringKey(Object? key) {
  if (key is String) {
    return key;
  }
  throw UnsupportedAnyValueException(
    value: key,
    reason: 'map keys must be strings',
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
