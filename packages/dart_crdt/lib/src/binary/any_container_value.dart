part of 'any_value.dart';

/// A binary-capable list value.
final class AnyList extends AnyValue {
  /// Creates an any-value list with a defensive copy of [values].
  AnyList(Iterable<AnyValue> values) : values = List.unmodifiable(values);

  /// The list elements.
  final List<AnyValue> values;

  @override
  List<Object?> toObject() => List<Object?>.unmodifiable(
        values.map((value) => value.toObject()),
      );

  @override
  bool operator ==(Object other) =>
      other is AnyList && _listEquals(values, other.values);

  @override
  int get hashCode => _listHash(values);
}

/// A binary-capable map value.
final class AnyMap extends AnyValue {
  /// Creates an any-value map with a defensive copy of [entries].
  AnyMap(Map<String, AnyValue> entries) : entries = Map.unmodifiable(entries);

  /// The map entries.
  final Map<String, AnyValue> entries;

  @override
  Map<String, Object?> toObject() => Map<String, Object?>.unmodifiable(
        entries.map((key, value) => MapEntry(key, value.toObject())),
      );

  @override
  bool operator ==(Object other) =>
      other is AnyMap && _stringMapEquals(entries, other.entries);

  @override
  int get hashCode => _stringMapHash(entries);
}

/// A binary payload value.
final class AnyBinary extends AnyValue {
  /// Creates a binary value with a defensive copy of [bytes].
  AnyBinary(List<int> bytes) : bytes = _copyBytes(bytes);

  /// The immutable binary payload.
  final Uint8List bytes;

  @override
  Uint8List toObject() => Uint8List.fromList(bytes).asUnmodifiableView();

  @override
  bool operator ==(Object other) =>
      other is AnyBinary && _listEquals(bytes, other.bytes);

  @override
  int get hashCode => _listHash(bytes);
}

Uint8List _copyBytes(List<int> bytes) {
  final copy = Uint8List(bytes.length);
  for (var index = 0; index < bytes.length; index += 1) {
    final byte = bytes[index];
    RangeError.checkValueInInterval(byte, 0, 255, 'bytes[$index]');
    copy[index] = byte;
  }
  return copy.asUnmodifiableView();
}
