/// Tagged binary codec for JSON-compatible and binary-capable values.
library;

import 'dart:typed_data';

import 'any_value.dart';
import 'byte_reader.dart';
import 'byte_writer.dart';
import 'string_buffer_codec.dart';
import 'varint_codec.dart';

const _tagNull = 0;
const _tagFalse = 1;
const _tagTrue = 2;
const _tagInteger = 3;
const _tagFloat64 = 4;
const _tagString = 5;
const _tagList = 6;
const _tagMap = 7;
const _tagBinary = 8;

/// Thrown when an encoded any-value payload is malformed.
final class MalformedAnyValueException implements FormatException {
  /// Creates an exception for malformed input at [offset].
  const MalformedAnyValueException({
    required this.offset,
    required this.reason,
  });

  @override
  final int offset;

  /// The reason decoding failed.
  final String reason;

  @override
  String get message => 'Malformed any-value at offset $offset: $reason.';

  @override
  Object? get source => null;

  @override
  String toString() => 'MalformedAnyValueException: $message';
}

/// Reads a JSON-compatible value from [reader].
JsonValue readJsonValue(ByteReader reader) {
  return _toJsonValue(readAnyValue(reader));
}

/// Writes a JSON-compatible [value] to [writer].
void writeJsonValue(ByteWriter writer, JsonValue value) {
  writeAnyValue(writer, value);
}

/// Reads an any-value from [reader].
AnyValue readAnyValue(ByteReader reader) {
  final tagOffset = reader.offset;
  final tag = reader.readByte();

  return switch (tag) {
    _tagNull => const JsonNull(),
    _tagFalse => const JsonBool(false),
    _tagTrue => const JsonBool(true),
    _tagInteger => JsonNumber(readVarInt(reader)),
    _tagFloat64 => JsonNumber(_readFloat64(reader)),
    _tagString => JsonString(readString(reader)),
    _tagList => AnyList(_readList(reader)),
    _tagMap => AnyMap(_readMap(reader)),
    _tagBinary => AnyBinary(readByteBuffer(reader)),
    _ => throw MalformedAnyValueException(
        offset: tagOffset,
        reason: 'unknown type tag $tag',
      ),
  };
}

/// Writes [value] to [writer].
void writeAnyValue(ByteWriter writer, AnyValue value) {
  switch (value) {
    case JsonNull():
      writer.writeByte(_tagNull);
    case JsonBool(value: false):
      writer.writeByte(_tagFalse);
    case JsonBool(value: true):
      writer.writeByte(_tagTrue);
    case JsonNumber(value: final number):
      _writeNumber(writer, number);
    case JsonString(value: final string):
      writer.writeByte(_tagString);
      writeString(writer, string);
    case JsonList(values: final values):
      _writeList(writer, values);
    case JsonMap(entries: final entries):
      _writeMap(writer, entries);
    case AnyList(values: final values):
      _writeList(writer, values);
    case AnyMap(entries: final entries):
      _writeMap(writer, entries);
    case AnyBinary(bytes: final bytes):
      writer.writeByte(_tagBinary);
      writeByteBuffer(writer, bytes);
  }
}

void _writeNumber(ByteWriter writer, num number) {
  if (number is int) {
    writer.writeByte(_tagInteger);
    writeVarInt(writer, number);
    return;
  }
  // JsonNumber construction already rejects non-finite values.
  // coverage:ignore-start
  if (!number.isFinite) {
    throw UnsupportedAnyValueException(
      value: number,
      reason: 'numbers must be finite',
    );
  }
  // coverage:ignore-end

  writer.writeByte(_tagFloat64);
  final data = ByteData(8)..setFloat64(0, number.toDouble(), Endian.little);
  writer.writeBytes(data.buffer.asUint8List());
}

double _readFloat64(ByteReader reader) {
  final bytes = reader.readBytes(8);
  final value = ByteData.sublistView(bytes).getFloat64(0, Endian.little);
  if (value.isFinite) {
    return value;
  }

  throw MalformedAnyValueException(
    offset: reader.offset - 8,
    reason: 'non-finite numbers are not supported',
  );
}

List<AnyValue> _readList(ByteReader reader) {
  final length = readVarUint(reader);
  return [
    for (var index = 0; index < length; index += 1) readAnyValue(reader),
  ];
}

Map<String, AnyValue> _readMap(ByteReader reader) {
  final length = readVarUint(reader);
  return {
    for (var index = 0; index < length; index += 1)
      readString(reader): readAnyValue(reader),
  };
}

void _writeList(ByteWriter writer, Iterable<AnyValue> values) {
  writer.writeByte(_tagList);
  writeVarUint(writer, values.length);
  for (final value in values) {
    writeAnyValue(writer, value);
  }
}

void _writeMap(ByteWriter writer, Map<String, AnyValue> entries) {
  writer.writeByte(_tagMap);
  writeVarUint(writer, entries.length);
  for (final entry in entries.entries) {
    writeString(writer, entry.key);
    writeAnyValue(writer, entry.value);
  }
}

JsonValue _toJsonValue(AnyValue value) {
  return switch (value) {
    JsonValue() => value,
    AnyList(values: final values) => JsonList(values.map(_toJsonValue)),
    AnyMap(entries: final entries) => JsonMap(
        entries.map((key, value) => MapEntry(key, _toJsonValue(value))),
      ),
    AnyBinary() => throw const MalformedAnyValueException(
        offset: 0,
        reason: 'binary payload is not valid JSON',
      ),
  };
}
