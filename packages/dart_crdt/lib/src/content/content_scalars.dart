part of 'content.dart';

/// Binary payload content.
final class ContentBinary extends AbstractContent {
  /// Creates binary content with a defensive copy of [bytes].
  ContentBinary(List<int> bytes) : bytes = _copyBytes(bytes);

  /// Stored immutable bytes.
  final Uint8List bytes;

  @override
  int get ref => contentBinaryRef;

  @override
  int get length => 1;

  @override
  bool get isCountable => true;

  @override
  List<Object?> get content => [Uint8List.fromList(bytes).asUnmodifiableView()];

  @override
  ContentBinary copy() => ContentBinary(bytes);

  @override
  ContentBinary splice(int offset) {
    throw UnsupportedError('Binary content cannot be split.');
  }

  @override
  bool mergeWith(AbstractContent right) => false;

  @override
  void write(ByteWriter writer, {int offset = 0, int offsetEnd = 0}) {
    encodedLength(offset: offset, offsetEnd: offsetEnd);
    writeByteBuffer(writer, bytes);
  }

  @override
  bool operator ==(Object other) {
    return other is ContentBinary && _listEquals(bytes, other.bytes);
  }

  @override
  int get hashCode => _listHash(bytes);
}

/// Deleted, non-countable content.
final class ContentDeleted extends AbstractContent {
  /// Creates deleted content with positive [length].
  ContentDeleted(int length)
      : length = RangeError.checkValueInInterval(
          length,
          1,
          maxSafeInteger,
          'length',
        );

  @override
  int length;

  @override
  int get ref => contentDeletedRef;

  @override
  bool get isCountable => false;

  @override
  List<Object?> get content => const <Object?>[];

  @override
  ContentDeleted copy() => ContentDeleted(length);

  @override
  ContentDeleted splice(int offset) {
    checkSplitOffset(offset);
    final right = ContentDeleted(length - offset);
    length = offset;
    return right;
  }

  @override
  bool mergeWith(AbstractContent right) {
    if (right is! ContentDeleted) {
      return false;
    }
    length += right.length;
    return true;
  }

  @override
  void integrate(ContentLifecycleTarget target) {
    target.markDeleted(length);
  }

  @override
  void write(ByteWriter writer, {int offset = 0, int offsetEnd = 0}) {
    writeVarUint(writer, encodedLength(offset: offset, offsetEnd: offsetEnd));
  }

  @override
  bool operator ==(Object other) {
    return other is ContentDeleted && length == other.length;
  }

  @override
  int get hashCode => length.hashCode;
}

/// Embedded JSON value content.
final class ContentEmbed extends AbstractContent {
  /// Creates embedded JSON content.
  ContentEmbed(Object? value) : value = JsonValue.fromObject(value);

  /// Stored embedded value.
  final JsonValue value;

  @override
  int get ref => contentEmbedRef;

  @override
  int get length => 1;

  @override
  bool get isCountable => true;

  @override
  List<Object?> get content => [value.toObject()];

  @override
  ContentEmbed copy() => ContentEmbed(value.toObject());

  @override
  ContentEmbed splice(int offset) {
    throw UnsupportedError('Embedded content cannot be split.');
  }

  @override
  bool mergeWith(AbstractContent right) => false;

  @override
  void write(ByteWriter writer, {int offset = 0, int offsetEnd = 0}) {
    encodedLength(offset: offset, offsetEnd: offsetEnd);
    writeJsonValue(writer, value);
  }

  @override
  bool operator ==(Object other) {
    return other is ContentEmbed && value == other.value;
  }

  @override
  int get hashCode => value.hashCode;
}

/// Non-countable format marker content.
final class ContentFormat extends AbstractContent {
  /// Creates format marker content.
  ContentFormat({
    required this.key,
    required Object? value,
  }) : value = JsonValue.fromObject(value);

  /// The format key.
  final String key;

  /// The format value.
  final JsonValue value;

  @override
  int get ref => contentFormatRef;

  @override
  int get length => 1;

  @override
  bool get isCountable => false;

  @override
  List<Object?> get content => const <Object?>[];

  @override
  ContentFormat copy() => ContentFormat(key: key, value: value.toObject());

  @override
  ContentFormat splice(int offset) {
    throw UnsupportedError('Format content cannot be split.');
  }

  @override
  bool mergeWith(AbstractContent right) => false;

  @override
  void integrate(ContentLifecycleTarget target) {
    target
      ..clearFormattingCache()
      ..markHasFormatting();
  }

  @override
  void write(ByteWriter writer, {int offset = 0, int offsetEnd = 0}) {
    encodedLength(offset: offset, offsetEnd: offsetEnd);
    writeString(writer, key);
    writeAnyValue(writer, AnyValue.fromObject(value.toObject()));
  }

  @override
  bool operator ==(Object other) {
    return other is ContentFormat && key == other.key && value == other.value;
  }

  @override
  int get hashCode => Object.hash(key, value);
}
