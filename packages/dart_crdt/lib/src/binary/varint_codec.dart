/// Variable-width integer codecs for binary update formats.
library;

import 'byte_reader.dart';
import 'byte_writer.dart';

/// The largest integer that can be represented exactly on every Dart platform.
const maxSafeInteger = 9007199254740991;

const _continuationBit = 128;
const _signedBit = 64;
const _unsignedBase = 128;
const _signedFirstBase = 64;
const _maxVarUintBytes = 8;
const _maxVarIntBytes = 8;
const _maxVarUintFinalPayload = 15;
const _maxVarIntFinalPayload = 31;

/// Thrown when a varint contains invalid continuation bytes or overflows.
final class MalformedVarintException implements Exception {
  /// Creates an exception describing an invalid varint byte sequence.
  const MalformedVarintException({
    required this.offset,
    required this.reason,
  });

  /// The byte offset where the malformed condition was detected.
  final int offset;

  /// The reason the varint could not be decoded.
  final String reason;

  /// A human-readable description of the malformed varint.
  String get message => 'Malformed varint at offset $offset: $reason.';

  @override
  String toString() => 'MalformedVarintException: $message';
}

/// Reads an unsigned base-128 varint from [reader].
int readVarUint(ByteReader reader) {
  var value = 0;
  var multiplier = 1;

  for (var byteIndex = 0; byteIndex < _maxVarUintBytes; byteIndex += 1) {
    final byte = reader.readByte();
    final payload = byte % _continuationBit;

    if (byteIndex == _maxVarUintBytes - 1) {
      _rejectInvalidFinalByte(
        byte: byte,
        payload: payload,
        maxPayload: _maxVarUintFinalPayload,
        offset: reader.offset - 1,
      );
    }

    value += payload * multiplier;
    _rejectOverflow(value: value, offset: reader.offset - 1);

    if (!_hasContinuation(byte)) {
      return value;
    }

    multiplier *= _unsignedBase;
  }

  // Final-byte validation rejects this condition before loop fallthrough.
  // coverage:ignore-start
  throw MalformedVarintException(
    offset: reader.offset,
    reason: 'unterminated continuation sequence',
  );
  // coverage:ignore-end
}

/// Writes [value] as an unsigned base-128 varint.
void writeVarUint(ByteWriter writer, int value) {
  RangeError.checkValueInInterval(value, 0, maxSafeInteger, 'value');

  var remaining = value;
  while (remaining >= _unsignedBase) {
    writer.writeByte((remaining % _unsignedBase) + _continuationBit);
    remaining ~/= _unsignedBase;
  }
  writer.writeByte(remaining);
}

/// Reads a signed varint from [reader].
int readVarInt(ByteReader reader) {
  final firstByte = reader.readByte();
  final firstPayload = firstByte % _continuationBit;
  final isNegative = firstPayload >= _signedBit;

  var value = firstPayload % _signedFirstBase;
  if (!_hasContinuation(firstByte)) {
    return isNegative ? -value : value;
  }

  var multiplier = _signedFirstBase;
  for (var byteIndex = 1; byteIndex < _maxVarIntBytes; byteIndex += 1) {
    final byte = reader.readByte();
    final payload = byte % _continuationBit;

    if (byteIndex == _maxVarIntBytes - 1) {
      _rejectInvalidFinalByte(
        byte: byte,
        payload: payload,
        maxPayload: _maxVarIntFinalPayload,
        offset: reader.offset - 1,
      );
    }

    value += payload * multiplier;
    _rejectOverflow(value: value, offset: reader.offset - 1);

    if (!_hasContinuation(byte)) {
      return isNegative ? -value : value;
    }

    multiplier *= _unsignedBase;
  }

  // Final-byte validation rejects this condition before loop fallthrough.
  // coverage:ignore-start
  throw MalformedVarintException(
    offset: reader.offset,
    reason: 'unterminated continuation sequence',
  );
  // coverage:ignore-end
}

/// Writes [value] as a signed varint.
void writeVarInt(ByteWriter writer, int value) {
  if (value < -maxSafeInteger || value > maxSafeInteger) {
    throw RangeError.range(
      value,
      -maxSafeInteger,
      maxSafeInteger,
      'value',
    );
  }

  final isNegative = value.isNegative;
  final magnitude = isNegative ? -value : value;
  var remaining = magnitude ~/ _signedFirstBase;
  var firstByte = magnitude % _signedFirstBase;

  if (isNegative) {
    firstByte += _signedBit;
  }
  if (remaining > 0) {
    firstByte += _continuationBit;
  }
  writer.writeByte(firstByte);

  while (remaining > 0) {
    final payload = remaining % _unsignedBase;
    remaining ~/= _unsignedBase;
    writer.writeByte(
      payload + (remaining > 0 ? _continuationBit : 0),
    );
  }
}

bool _hasContinuation(int byte) => byte >= _continuationBit;

void _rejectInvalidFinalByte({
  required int byte,
  required int payload,
  required int maxPayload,
  required int offset,
}) {
  if (_hasContinuation(byte)) {
    throw MalformedVarintException(
      offset: offset,
      reason: 'too many continuation bytes',
    );
  }
  if (payload > maxPayload) {
    throw MalformedVarintException(
      offset: offset,
      reason: 'encoded value exceeds maxSafeInteger',
    );
  }
}

void _rejectOverflow({
  required int value,
  required int offset,
}) {
  if (value <= maxSafeInteger) {
    return;
  }

  // Final-byte validation rejects overflow before this defensive fallback.
  // coverage:ignore-start
  throw MalformedVarintException(
    offset: offset,
    reason: 'encoded value exceeds maxSafeInteger',
  );
  // coverage:ignore-end
}
