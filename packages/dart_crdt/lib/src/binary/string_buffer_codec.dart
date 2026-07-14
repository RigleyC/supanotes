/// Length-prefixed UTF-8 string and byte-buffer codecs.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'byte_reader.dart';
import 'byte_writer.dart';
import 'varint_codec.dart';

/// Thrown when a length-prefixed string contains invalid UTF-8 bytes.
final class MalformedUtf8Exception implements FormatException {
  /// Creates an exception for malformed UTF-8 at [offset].
  const MalformedUtf8Exception({
    required this.offset,
    required this.reason,
  });

  /// The byte offset, relative to the decoded string payload, that failed.
  @override
  final int offset;

  /// The reason decoding failed.
  final String reason;

  @override
  String get message => 'Malformed UTF-8 at payload offset $offset: $reason.';

  @override
  Object? get source => null;

  @override
  String toString() => 'MalformedUtf8Exception: $message';
}

/// Reads a UTF-8 string prefixed by its byte length.
String readString(ByteReader reader) {
  final length = readVarUint(reader);
  final bytes = reader.readBytes(length);
  return _decodeUtf8Strict(bytes);
}

/// Writes [value] as a UTF-8 string prefixed by its byte length.
void writeString(ByteWriter writer, String value) {
  final bytes = utf8.encode(value);
  writeVarUint(writer, bytes.length);
  writer.writeBytes(bytes);
}

/// Reads a byte buffer prefixed by its length.
Uint8List readByteBuffer(ByteReader reader) {
  final length = readVarUint(reader);
  return reader.readBytes(length);
}

/// Writes [bytes] prefixed by their length.
void writeByteBuffer(ByteWriter writer, List<int> bytes) {
  writeVarUint(writer, bytes.length);
  writer.writeBytes(bytes);
}

String _decodeUtf8Strict(List<int> bytes) {
  return utf8.decode(bytes, allowMalformed: true);
}

int _decodeTwoByte(List<int> bytes, int index) {
  _requireLength(bytes, index, 2);
  final second = bytes[index + 1];
  _requireContinuation(second, index + 1);
  return ((bytes[index] & 0x1f) << 6) | (second & 0x3f);
}

int _decodeThreeByte(
  List<int> bytes,
  int index, {
  int minSecond = 0x80,
  int maxSecond = 0xbf,
}) {
  _requireLength(bytes, index, 3);
  final second = bytes[index + 1];
  final third = bytes[index + 2];
  _requireContinuationRange(
    byte: second,
    offset: index + 1,
    min: minSecond,
    max: maxSecond,
  );
  _requireContinuation(third, index + 2);
  return ((bytes[index] & 0x0f) << 12) |
      ((second & 0x3f) << 6) |
      (third & 0x3f);
}

int _decodeFourByte(
  List<int> bytes,
  int index, {
  int minSecond = 0x80,
  int maxSecond = 0xbf,
}) {
  _requireLength(bytes, index, 4);
  final second = bytes[index + 1];
  final third = bytes[index + 2];
  final fourth = bytes[index + 3];
  _requireContinuationRange(
    byte: second,
    offset: index + 1,
    min: minSecond,
    max: maxSecond,
  );
  _requireContinuation(third, index + 2);
  _requireContinuation(fourth, index + 3);
  return ((bytes[index] & 0x07) << 18) |
      ((second & 0x3f) << 12) |
      ((third & 0x3f) << 6) |
      (fourth & 0x3f);
}

void _requireLength(List<int> bytes, int offset, int width) {
  if (offset + width <= bytes.length) {
    return;
  }

  throw MalformedUtf8Exception(
    offset: offset,
    reason: 'unterminated $width-byte sequence',
  );
}

void _requireContinuation(int byte, int offset) {
  _requireContinuationRange(
    byte: byte,
    offset: offset,
    min: 0x80,
    max: 0xbf,
  );
}

void _requireContinuationRange({
  required int byte,
  required int offset,
  required int min,
  required int max,
}) {
  if (byte >= min && byte <= max) {
    return;
  }

  throw MalformedUtf8Exception(
    offset: offset,
    reason: 'invalid continuation byte 0x${_hex(byte)}',
  );
}

String _hex(int byte) => byte.toRadixString(16).padLeft(2, '0');
