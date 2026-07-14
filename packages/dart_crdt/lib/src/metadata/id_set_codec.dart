/// Binary codecs for id sets.
library;

import 'dart:typed_data';

import '../binary/byte_reader.dart';
import '../binary/byte_writer.dart';
import '../binary/varint_codec.dart';
import '../structs/id.dart';
import 'id_range.dart';
import 'id_set.dart';

/// V1 binary writer for id sets and update delete-set fields.
base class IdSetEncoderV1 {
  /// Creates an empty V1 id-set field encoder.
  IdSetEncoderV1() : _writer = ByteWriter();

  final ByteWriter _writer;
  Uint8List? _closedBytes;

  /// Writer used for direct V1 fields.
  ByteWriter get restWriter {
    _ensureWritable();
    return _writer;
  }

  /// Returns immutable encoded bytes and closes this encoder.
  Uint8List toBytes() {
    return _closedBytes ??= _writer.toBytes();
  }

  /// Resets the current delete-set clock.
  void resetIdSetCurVal() {}

  /// Writes an absolute delete-set [clock].
  void writeIdSetClock(Clock clock) {
    writeClock(restWriter, clock);
  }

  /// Writes a delete-set range [length].
  void writeIdSetLen(int length) {
    RangeError.checkValueInInterval(length, 0, maxSafeInteger, 'length');
    writeVarUint(restWriter, length);
  }

  /// Writes [set] to [writer].
  static void write(ByteWriter writer, IdSet set) {
    _writeIdSet(writer, set);
  }

  void _ensureWritable() {
    if (_closedBytes != null) {
      throw StateError('Cannot write after encoding has been finalized.');
    }
  }
}

/// V1 binary reader for id sets and update delete-set fields.
base class IdSetDecoderV1 {
  /// Creates a V1 id-set field decoder over [bytes].
  IdSetDecoderV1(List<int> bytes) : this.fromReader(ByteReader(bytes));

  /// Creates a V1 id-set field decoder from [reader].
  IdSetDecoderV1.fromReader(ByteReader reader) : restReader = reader;

  /// Reader used for direct V1 fields.
  final ByteReader restReader;

  /// Resets the current delete-set clock.
  void resetIdSetCurVal() {}

  /// Reads an absolute delete-set clock.
  Clock readIdSetClock() {
    return readClock(restReader);
  }

  /// Reads a delete-set range length.
  int readIdSetLen() {
    return readVarUint(restReader);
  }

  /// Reads an id set from [reader].
  static IdSet read(ByteReader reader) {
    return _readIdSet(reader);
  }
}

/// V2 binary writer for id sets and update delete-set fields.
base class IdSetEncoderV2 {
  /// Creates an empty V2 id-set field encoder.
  IdSetEncoderV2() : _writer = ByteWriter();

  final ByteWriter _writer;
  Uint8List? _closedBytes;
  int _currentClock = 0;

  /// Writer used for direct V2 rest fields.
  ByteWriter get restWriter {
    _ensureWritable();
    return _writer;
  }

  /// Returns immutable encoded bytes and closes this encoder.
  Uint8List toBytes() {
    return _closedBytes ??= _writer.toBytes();
  }

  /// Resets the current delete-set clock diff base.
  void resetIdSetCurVal() {
    _currentClock = 0;
  }

  /// Writes [clock] as a diff from the current delete-set clock.
  void writeIdSetClock(Clock clock) {
    if (clock.value < _currentClock) {
      throw RangeError.range(
        clock.value,
        _currentClock,
        maxSafeInteger,
        'clock',
      );
    }
    writeVarUint(restWriter, clock.value - _currentClock);
    _currentClock = clock.value;
  }

  /// Writes a non-empty delete-set range [length].
  void writeIdSetLen(int length) {
    RangeError.checkValueInInterval(length, 1, maxSafeInteger, 'length');
    writeVarUint(restWriter, length - 1);
    _currentClock += length;
  }

  /// Writes [set] to [writer].
  static void write(ByteWriter writer, IdSet set) {
    _writeIdSet(writer, set);
  }

  void _ensureWritable() {
    if (_closedBytes != null) {
      throw StateError('Cannot write after encoding has been finalized.');
    }
  }
}

/// V2 binary reader for id sets and update delete-set fields.
base class IdSetDecoderV2 {
  /// Creates a V2 id-set field decoder over [bytes].
  IdSetDecoderV2(List<int> bytes) : this.fromReader(ByteReader(bytes));

  /// Creates a V2 id-set field decoder from [reader].
  IdSetDecoderV2.fromReader(ByteReader reader) : restReader = reader;

  /// Reader used for direct V2 rest fields.
  final ByteReader restReader;
  int _currentClock = 0;

  /// Resets the current delete-set clock diff base.
  void resetIdSetCurVal() {
    _currentClock = 0;
  }

  /// Reads a diff-encoded delete-set clock.
  Clock readIdSetClock() {
    _currentClock += readVarUint(restReader);
    return Clock(_currentClock);
  }

  /// Reads a non-empty delete-set range length.
  int readIdSetLen() {
    final length = readVarUint(restReader) + 1;
    _currentClock += length;
    return length;
  }

  /// Reads an id set from [reader].
  static IdSet read(ByteReader reader) {
    return _readIdSet(reader);
  }
}

void _writeIdSet(ByteWriter writer, IdSet set) {
  writeVarUint(writer, set.clientCount);
  for (final client in set.clients) {
    final ranges = set.rangesFor(client);
    writeClientId(writer, client);
    writeVarUint(writer, ranges.length);
    for (final range in ranges) {
      writeClock(writer, range.start);
      writeVarUint(writer, range.length);
    }
  }
}

IdSet _readIdSet(ByteReader reader) {
  final clientCount = readVarUint(reader);
  final set = IdSet();
  for (var clientIndex = 0; clientIndex < clientCount; clientIndex += 1) {
    final client = readClientId(reader);
    final rangeCount = readVarUint(reader);
    for (var rangeIndex = 0; rangeIndex < rangeCount; rangeIndex += 1) {
      final start = readClock(reader);
      final length = readVarUint(reader);
      set.addRange(client, IdRange(start: start, length: length));
    }
  }
  return set;
}
