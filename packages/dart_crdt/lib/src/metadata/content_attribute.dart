/// Immutable content attribution values.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../binary/any_value.dart';

/// Metadata attached to a client-local content range.
final class ContentAttribute {
  /// Creates an attribute by converting [value] to an any-value.
  factory ContentAttribute(String name, Object? value) {
    return ContentAttribute.fromAny(
      name: name,
      value: AnyValue.fromObject(value),
    );
  }

  /// Creates an attribute from a pre-built any-value [value].
  ContentAttribute.fromAny({
    required this.name,
    required this.value,
  });

  /// The attribute name.
  final String name;

  /// The attribute payload.
  final AnyValue value;

  late final String _stableKey = _attributeKey(name, value);

  /// A deterministic content key for this attribute.
  String get stableKey => _stableKey;

  /// A deterministic short hash for this attribute.
  String get stableHash => _fnv64Hex(_stableKey);

  /// Converts this attribute to a JSON-compatible object where possible.
  Map<String, Object?> toJson() => {
        'name': name,
        'value': value.toObject(),
      };

  @override
  bool operator ==(Object other) {
    return other is ContentAttribute &&
        name == other.name &&
        value == other.value;
  }

  @override
  int get hashCode => Object.hash(name, value);

  @override
  String toString() => '$name=${value.toObject()}';
}

/// Returns unique attributes sorted by deterministic content identity.
List<ContentAttribute> normalizeContentAttributes(
  Iterable<ContentAttribute> attributes,
) {
  final byKey = <String, ContentAttribute>{};
  for (final attribute in attributes) {
    byKey.putIfAbsent(attribute.stableKey, () => attribute);
  }

  final normalized = byKey.values.toList()
    ..sort((left, right) => left.stableKey.compareTo(right.stableKey));
  return List.unmodifiable(normalized);
}

/// Returns whether two normalized attribute lists describe the same set.
bool contentAttributesEqual(
  List<ContentAttribute> left,
  List<ContentAttribute> right,
) {
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

String _attributeKey(String name, AnyValue value) {
  return 'attr:${_stringKey(name)}:${_valueKey(value)}';
}

String _valueKey(AnyValue value) {
  return switch (value) {
    JsonNull() => 'n',
    JsonBool(value: final boolValue) => 'b:${boolValue ? 1 : 0}',
    JsonNumber(value: final number) => _numberKey(number),
    JsonString(value: final string) => 's:${_stringKey(string)}',
    JsonList(values: final values) => _listKey(values),
    JsonMap(entries: final entries) => _jsonMapKey(entries),
    AnyList(values: final values) => _listKey(values),
    AnyMap(entries: final entries) => _anyMapKey(entries),
    AnyBinary(bytes: final bytes) => 'x:${base64UrlEncode(bytes)}',
  };
}

String _numberKey(num number) {
  if (number == 0) {
    return 'i:0';
  }
  if (number is int) {
    return 'i:$number';
  }
  if (number % 1 == 0) {
    return 'i:${number.toInt()}';
  }
  return 'd:${number.toString()}';
}

String _listKey(Iterable<AnyValue> values) {
  return 'l:[${values.map(_valueKey).join(',')}]';
}

String _jsonMapKey(Map<String, JsonValue> entries) {
  return _mapKey({
    for (final entry in entries.entries) entry.key: entry.value,
  });
}

String _anyMapKey(Map<String, AnyValue> entries) {
  return _mapKey(entries);
}

String _mapKey(Map<String, AnyValue> entries) {
  final keys = entries.keys.toList()..sort();
  final parts = <String>[
    for (final key in keys) '${_stringKey(key)}:${_valueKey(entries[key]!)}',
  ];
  return 'm:{${parts.join(',')}}';
}

String _stringKey(String value) {
  return base64UrlEncode(utf8.encode(value));
}

/// Computes a deterministic 64-bit FNV-1a-style digest as 16 lowercase hex
/// digits.
///
/// The classic 64-bit algorithm relies on integer constants and products that
/// exceed 2^53, which dart2js cannot represent exactly (and which fail to even
/// compile as literals). This implementation keeps all arithmetic within two
/// independent 32-bit lanes using only `%`, `~/`, `*` and 16-bit `^`, every
/// one of which is exact on both the Dart VM and the web. The digest is
/// therefore identical across every platform.
String _fnv64Hex(String value) {
  final bytes = Uint8List.fromList(utf8.encode(value));
  // Two FNV-1a lanes with distinct seeds/primes form the high and low words.
  final hi = _fnv32(bytes, 0x811c9dc5, 16777619);
  final lo = _fnv32(bytes, 0x01000193, 16777639);
  return _hex32(hi) + _hex32(lo);
}

int _fnv32(Uint8List bytes, int seed, int prime) {
  var hash = seed;
  for (final byte in bytes) {
    hash = _mul32(_xor32(hash, byte), prime);
  }
  return hash;
}

/// Multiplies two unsigned 32-bit integers, returning the low 32 bits. Every
/// intermediate product stays below 2^53 so the result is exact everywhere.
int _mul32(int a, int b) {
  final aLow = a % 0x10000;
  final aHigh = a ~/ 0x10000;
  return (aLow * b + (aHigh * b % 0x10000) * 0x10000) % 0x100000000;
}

/// XORs two unsigned 32-bit integers without relying on platform-dependent
/// 32-bit bitwise semantics: each `^` operates on 16-bit (always-positive)
/// halves, so the result matches on the VM and the web.
int _xor32(int a, int b) {
  final low = (a % 0x10000) ^ (b % 0x10000);
  final high = (a ~/ 0x10000) ^ (b ~/ 0x10000);
  return high * 0x10000 + low;
}

String _hex32(int value) => value.toRadixString(16).padLeft(8, '0');
