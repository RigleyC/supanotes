/// Optimized RLE codecs for unsigned integers and integer diffs.
library;

import 'dart:typed_data';

import 'byte_reader.dart';
import 'byte_writer.dart';
import 'varint_codec.dart';

/// Encodes unsigned integers, storing repeated values as signed run markers.
final class UintOptRleEncoder {
  /// Creates an empty optimized unsigned integer RLE encoder.
  UintOptRleEncoder() : _writer = ByteWriter();

  final ByteWriter _writer;
  int _state = 0;
  int _count = 0;
  Uint8List? _closedBytes;

  /// Writes [value] to the stream.
  void write(int value) {
    _ensureWritable(_closedBytes);
    RangeError.checkValueInInterval(value, 0, maxSafeInteger, 'value');
    if (_state == value && _count > 0) {
      _count += 1;
      return;
    }
    _flushUintOptRun(_writer, _state, _count);
    _state = value;
    _count = 1;
  }

  /// Returns immutable encoded bytes and closes this encoder.
  Uint8List toBytes() {
    if (_closedBytes != null) {
      return _closedBytes!;
    }
    _flushUintOptRun(_writer, _state, _count);
    return _closedBytes ??= _writer.toBytes();
  }
}

/// Decodes values produced by [UintOptRleEncoder].
final class UintOptRleDecoder {
  /// Creates a decoder over [bytes].
  UintOptRleDecoder(List<int> bytes) : _reader = ByteReader(bytes);

  final ByteReader _reader;
  int _state = 0;
  int _count = 0;

  /// Reads the next decoded value.
  int read() {
    if (_count == 0) {
      final signed = _readSignedMagnitude(_reader);
      _state = signed.magnitude;
      _count = signed.isNegative ? readVarUint(_reader) + 2 : 1;
    }
    _count -= 1;
    return _state;
  }

  /// Reads exactly [count] decoded values.
  List<int> readAll(int count) {
    RangeError.checkNotNegative(count, 'count');
    return List<int>.generate(count, (_) => read(), growable: false);
  }
}

/// Encodes consecutive increasing unsigned integers as optimized runs.
final class IncreasingUintOptRleEncoder {
  /// Creates an empty increasing unsigned integer RLE encoder.
  IncreasingUintOptRleEncoder() : _writer = ByteWriter();

  final ByteWriter _writer;
  int _state = 0;
  int _count = 0;
  Uint8List? _closedBytes;

  /// Writes [value] to the stream.
  void write(int value) {
    _ensureWritable(_closedBytes);
    RangeError.checkValueInInterval(value, 0, maxSafeInteger, 'value');
    if (_state + _count == value && _count > 0) {
      _count += 1;
      return;
    }
    _flushUintOptRun(_writer, _state, _count);
    _state = value;
    _count = 1;
  }

  /// Returns immutable encoded bytes and closes this encoder.
  Uint8List toBytes() {
    if (_closedBytes != null) {
      return _closedBytes!;
    }
    _flushUintOptRun(_writer, _state, _count);
    return _closedBytes ??= _writer.toBytes();
  }
}

/// Decodes values produced by [IncreasingUintOptRleEncoder].
final class IncreasingUintOptRleDecoder {
  /// Creates a decoder over [bytes].
  IncreasingUintOptRleDecoder(List<int> bytes) : _reader = ByteReader(bytes);

  final ByteReader _reader;
  int _state = 0;
  int _count = 0;

  /// Reads the next decoded value.
  int read() {
    if (_count == 0) {
      final signed = _readSignedMagnitude(_reader);
      _state = signed.magnitude;
      _count = signed.isNegative ? readVarUint(_reader) + 2 : 1;
    }
    _count -= 1;
    final value = _state;
    _state += 1;
    return value;
  }

  /// Reads exactly [count] decoded values.
  List<int> readAll(int count) {
    RangeError.checkNotNegative(count, 'count');
    return List<int>.generate(count, (_) => read(), growable: false);
  }
}

/// Encodes integer values by optimized run-length encoding repeated diffs.
final class IntDiffOptRleEncoder {
  /// Creates an empty optimized integer diff RLE encoder.
  IntDiffOptRleEncoder() : _writer = ByteWriter();

  final ByteWriter _writer;
  int _state = 0;
  int _diff = 0;
  int _count = 0;
  Uint8List? _closedBytes;

  /// Writes [value] to the stream.
  void write(int value) {
    _ensureWritable(_closedBytes);
    final diff = value - _state;
    if (_diff == diff && _count > 0) {
      _state = value;
      _count += 1;
      return;
    }
    _flushIntDiffOptRun(_writer, _diff, _count);
    _diff = diff;
    _state = value;
    _count = 1;
  }

  /// Returns immutable encoded bytes and closes this encoder.
  Uint8List toBytes() {
    if (_closedBytes != null) {
      return _closedBytes!;
    }
    _flushIntDiffOptRun(_writer, _diff, _count);
    return _closedBytes ??= _writer.toBytes();
  }
}

/// Decodes values produced by [IntDiffOptRleEncoder].
final class IntDiffOptRleDecoder {
  /// Creates a decoder over [bytes].
  IntDiffOptRleDecoder(List<int> bytes) : _reader = ByteReader(bytes);

  final ByteReader _reader;
  int _state = 0;
  int _diff = 0;
  int _count = 0;

  /// Reads the next decoded value.
  int read() {
    if (_count == 0) {
      final encodedDiff = readVarInt(_reader);
      _diff = (encodedDiff / 2).floor();
      _count = encodedDiff.isOdd ? readVarUint(_reader) + 2 : 1;
    }
    _state += _diff;
    _count -= 1;
    return _state;
  }

  /// Reads exactly [count] decoded values.
  List<int> readAll(int count) {
    RangeError.checkNotNegative(count, 'count');
    return List<int>.generate(count, (_) => read(), growable: false);
  }
}

void _flushUintOptRun(ByteWriter writer, int state, int count) {
  if (count == 0) {
    return;
  }
  _writeSignedMagnitude(
    writer,
    magnitude: state,
    isNegative: count > 1,
  );
  if (count > 1) {
    writeVarUint(writer, count - 2);
  }
}

void _flushIntDiffOptRun(ByteWriter writer, int diff, int count) {
  if (count == 0) {
    return;
  }
  writeVarInt(writer, diff * 2 + (count == 1 ? 0 : 1));
  if (count > 1) {
    writeVarUint(writer, count - 2);
  }
}

void _ensureWritable(Uint8List? closedBytes) {
  if (closedBytes != null) {
    throw StateError('Cannot write after encoding has been finalized.');
  }
}

void _writeSignedMagnitude(
  ByteWriter writer, {
  required int magnitude,
  required bool isNegative,
}) {
  RangeError.checkValueInInterval(magnitude, 0, maxSafeInteger, 'magnitude');
  var remaining = magnitude ~/ 64;
  var firstByte = magnitude % 64;
  if (isNegative) {
    firstByte += 64;
  }
  if (remaining > 0) {
    firstByte += 128;
  }
  writer.writeByte(firstByte);
  while (remaining > 0) {
    final payload = remaining % 128;
    remaining ~/= 128;
    writer.writeByte(payload + (remaining > 0 ? 128 : 0));
  }
}

({bool isNegative, int magnitude}) _readSignedMagnitude(ByteReader reader) {
  final firstByte = reader.readByte();
  final firstPayload = firstByte % 128;
  final isNegative = firstPayload >= 64;
  var magnitude = firstPayload % 64;
  if (firstByte < 128) {
    return (isNegative: isNegative, magnitude: magnitude);
  }

  var multiplier = 64;
  for (var index = 1; index < 8; index += 1) {
    final byte = reader.readByte();
    final payload = byte % 128;
    magnitude += payload * multiplier;
    if (magnitude > maxSafeInteger) {
      throw MalformedVarintException(
        offset: reader.offset - 1,
        reason: 'encoded value exceeds maxSafeInteger',
      );
    }
    if (byte < 128) {
      return (isNegative: isNegative, magnitude: magnitude);
    }
    multiplier *= 128;
  }

  throw MalformedVarintException(
    offset: reader.offset,
    reason: 'too many continuation bytes',
  );
}
