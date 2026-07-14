part of 'content.dart';

/// Arbitrary value array content.
final class ContentAny extends AbstractContent {
  /// Creates arbitrary value content.
  ContentAny(Iterable<AnyValue> values) : values = _immutableCopy(values);

  /// Converts Dart values into arbitrary value content.
  factory ContentAny.fromObjects(Iterable<Object?> values) {
    return ContentAny(values.map(AnyValue.fromObject));
  }

  /// Stored arbitrary values.
  List<AnyValue> values;

  @override
  int get ref => contentAnyRef;

  @override
  int get length => values.length;

  @override
  bool get isCountable => true;

  @override
  List<Object?> get content {
    return List<Object?>.unmodifiable(values.map((value) => value.toObject()));
  }

  @override
  ContentAny copy() => ContentAny(values);

  @override
  ContentAny splice(int offset) {
    checkSplitOffset(offset);
    final right = ContentAny(values.skip(offset));
    values = _immutableCopy(values.take(offset));
    return right;
  }

  @override
  bool mergeWith(AbstractContent right) {
    if (right is! ContentAny) {
      return false;
    }
    values = _immutableCopy(<AnyValue>[...values, ...right.values]);
    return true;
  }

  @override
  void write(ByteWriter writer, {int offset = 0, int offsetEnd = 0}) {
    final count = encodedLength(offset: offset, offsetEnd: offsetEnd);
    writeVarUint(writer, count);
    for (final value in values.skip(offset).take(count)) {
      writeAnyValue(writer, value);
    }
  }

  @override
  bool operator ==(Object other) {
    return other is ContentAny && _listEquals(values, other.values);
  }

  @override
  int get hashCode => _listHash(values);
}

/// JSON array content.
final class ContentJson extends AbstractContent {
  /// Creates JSON content.
  ContentJson(Iterable<JsonValue> values) : values = _immutableCopy(values);

  /// Converts Dart JSON values into JSON content.
  factory ContentJson.fromObjects(Iterable<Object?> values) {
    return ContentJson(values.map(JsonValue.fromObject));
  }

  /// Stored JSON values.
  List<JsonValue> values;

  @override
  int get ref => contentJsonRef;

  @override
  int get length => values.length;

  @override
  bool get isCountable => true;

  @override
  List<Object?> get content {
    return List<Object?>.unmodifiable(values.map((value) => value.toObject()));
  }

  @override
  ContentJson copy() => ContentJson(values);

  @override
  ContentJson splice(int offset) {
    checkSplitOffset(offset);
    final right = ContentJson(values.skip(offset));
    values = _immutableCopy(values.take(offset));
    return right;
  }

  @override
  bool mergeWith(AbstractContent right) {
    if (right is! ContentJson) {
      return false;
    }
    values = _immutableCopy(<JsonValue>[...values, ...right.values]);
    return true;
  }

  @override
  void write(ByteWriter writer, {int offset = 0, int offsetEnd = 0}) {
    final count = encodedLength(offset: offset, offsetEnd: offsetEnd);
    writeVarUint(writer, count);
    for (final value in values.skip(offset).take(count)) {
      writeString(writer, jsonEncode(value.toObject()));
    }
  }

  @override
  bool operator ==(Object other) {
    return other is ContentJson && _listEquals(values, other.values);
  }

  @override
  int get hashCode => _listHash(values);
}

/// UTF-16 string content.
final class ContentString extends AbstractContent {
  /// Creates string content.
  ContentString(this.value);

  /// Stored string value.
  String value;

  @override
  int get ref => contentStringRef;

  @override
  int get length => value.length;

  @override
  bool get isCountable => true;

  @override
  List<Object?> get content => List<Object?>.unmodifiable(value.split(''));

  @override
  ContentString copy() => ContentString(value);

  @override
  ContentString splice(int offset) {
    checkSplitOffset(offset);
    final right = ContentString(value.substring(offset));
    value = value.substring(0, offset);
    _repairSplitSurrogatePair(right);
    return right;
  }

  @override
  bool mergeWith(AbstractContent right) {
    if (right is! ContentString) {
      return false;
    }
    value += right.value;
    return true;
  }

  @override
  void write(ByteWriter writer, {int offset = 0, int offsetEnd = 0}) {
    encodedLength(offset: offset, offsetEnd: offsetEnd);
    writeString(writer, value.substring(offset, value.length - offsetEnd));
  }

  @override
  bool operator ==(Object other) {
    return other is ContentString && value == other.value;
  }

  @override
  int get hashCode => value.hashCode;

  void _repairSplitSurrogatePair(ContentString right) {
    final lastCode = value.codeUnitAt(value.length - 1);
    if (lastCode < 0xd800 || lastCode > 0xdbff) {
      return;
    }
    value = '${value.substring(0, value.length - 1)}\ufffd';
    right.value = '\ufffd${right.value.substring(1)}';
  }
}
