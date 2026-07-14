/// Run-length codecs for integer streams used by update encoders.
library;

import 'dart:typed_data';

import 'byte_reader.dart';
import 'byte_writer.dart';
import 'varint_codec.dart';

/// Encodes signed integers with basic run-length encoding.
final class RleIntEncoder {
  /// Creates an empty signed integer RLE encoder.
  RleIntEncoder() : _writer = ByteWriter();

  final ByteWriter _writer;
  int? _state;
  int _count = 0;
  Uint8List? _closedBytes;

  /// Writes [value] to the stream.
  void write(int value) {
    _ensureWritable(_closedBytes);
    if (_state == value) {
      _count += 1;
      return;
    }
    _flushRunLength(_writer, _count);
    _count = 1;
    _state = value;
    writeVarInt(_writer, value);
  }

  /// Returns immutable encoded bytes and closes this encoder.
  Uint8List toBytes() {
    return _closedBytes ??= _writer.toBytes();
  }
}

/// Decodes signed integers produced by [RleIntEncoder].
final class RleIntDecoder {
  /// Creates a decoder over [bytes].
  RleIntDecoder(List<int> bytes) : _reader = ByteReader(bytes);

  final ByteReader _reader;
  int? _state;
  int _count = 0;

  /// Reads the next decoded value.
  int read() {
    if (_count == 0) {
      _state = readVarInt(_reader);
      _count = _reader.remaining > 0 ? readVarUint(_reader) + 1 : -1;
    }
    _count -= 1;
    return _state!;
  }

  /// Reads exactly [count] decoded values.
  List<int> readAll(int count) {
    RangeError.checkNotNegative(count, 'count');
    return List<int>.generate(count, (_) => read(), growable: false);
  }
}

/// Encodes unsigned integers with basic run-length encoding.
final class UintRleEncoder {
  /// Creates an empty unsigned integer RLE encoder.
  UintRleEncoder() : _writer = ByteWriter();

  final ByteWriter _writer;
  int? _state;
  int _count = 0;
  Uint8List? _closedBytes;

  /// Writes [value] to the stream.
  void write(int value) {
    _ensureWritable(_closedBytes);
    RangeError.checkValueInInterval(value, 0, maxSafeInteger, 'value');
    if (_state == value) {
      _count += 1;
      return;
    }
    _flushRunLength(_writer, _count);
    _count = 1;
    _state = value;
    writeVarUint(_writer, value);
  }

  /// Returns immutable encoded bytes and closes this encoder.
  Uint8List toBytes() {
    return _closedBytes ??= _writer.toBytes();
  }
}

/// Decodes unsigned integers produced by [UintRleEncoder].
final class UintRleDecoder {
  /// Creates a decoder over [bytes].
  UintRleDecoder(List<int> bytes) : _reader = ByteReader(bytes);

  final ByteReader _reader;
  int? _state;
  int _count = 0;

  /// Reads the next decoded value.
  int read() {
    if (_count == 0) {
      _state = readVarUint(_reader);
      _count = _reader.remaining > 0 ? readVarUint(_reader) + 1 : -1;
    }
    _count -= 1;
    return _state!;
  }

  /// Reads exactly [count] decoded values.
  List<int> readAll(int count) {
    RangeError.checkNotNegative(count, 'count');
    return List<int>.generate(count, (_) => read(), growable: false);
  }
}

/// Encodes integer values by run-length encoding repeated decoded values.
final class IntDiffRleEncoder {
  /// Creates an encoder whose previous value starts at [start].
  IntDiffRleEncoder({int start = 0})
      : _state = start,
        _writer = ByteWriter();

  final ByteWriter _writer;
  int _state;
  int _count = 0;
  Uint8List? _closedBytes;

  /// Writes [value] to the stream.
  void write(int value) {
    _ensureWritable(_closedBytes);
    if (_state == value && _count > 0) {
      _count += 1;
      return;
    }
    _flushRunLength(_writer, _count);
    _count = 1;
    writeVarInt(_writer, value - _state);
    _state = value;
  }

  /// Returns immutable encoded bytes and closes this encoder.
  Uint8List toBytes() {
    return _closedBytes ??= _writer.toBytes();
  }
}

/// Decodes values produced by [IntDiffRleEncoder].
final class IntDiffRleDecoder {
  /// Creates a decoder over [bytes] whose previous value starts at [start].
  IntDiffRleDecoder(List<int> bytes, {int start = 0})
      : _state = start,
        _reader = ByteReader(bytes);

  final ByteReader _reader;
  int _state;
  int _count = 0;

  /// Reads the next decoded value.
  int read() {
    if (_count == 0) {
      _state += readVarInt(_reader);
      _count = _reader.remaining > 0 ? readVarUint(_reader) + 1 : -1;
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

void _flushRunLength(ByteWriter writer, int count) {
  if (count > 0) {
    writeVarUint(writer, count - 1);
  }
}

void _ensureWritable(Uint8List? closedBytes) {
  if (closedBytes != null) {
    throw StateError('Cannot write after encoding has been finalized.');
  }
}
