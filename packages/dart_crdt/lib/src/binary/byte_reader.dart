/// Bounds-checked byte reader primitives for binary codecs.
library;

import 'dart:typed_data';

/// Thrown when a binary reader cannot satisfy a requested byte count.
final class TruncatedInputException implements Exception {
  /// Creates an exception for a read that needs more bytes than remain.
  const TruncatedInputException({
    required this.offset,
    required this.expected,
    required this.remaining,
  });

  /// The byte offset where the failed read started.
  final int offset;

  /// The number of bytes requested by the failed read.
  final int expected;

  /// The number of bytes still available at [offset].
  final int remaining;

  /// A human-readable description of the failed read.
  String get message =>
      'Truncated binary input at offset $offset: expected $expected byte(s), '
      'but only $remaining remain.';

  @override
  String toString() => 'TruncatedInputException: $message';
}

/// Reads bytes from an immutable in-memory buffer.
final class ByteReader {
  /// Creates a reader over a defensive copy of [bytes].
  ByteReader(List<int> bytes) : _bytes = _copyBytes(bytes);

  final Uint8List _bytes;
  int _offset = 0;

  /// The total number of bytes in this reader.
  int get length => _bytes.length;

  /// The next byte offset that will be read.
  int get offset => _offset;

  /// The number of unread bytes remaining.
  int get remaining => _bytes.length - _offset;

  /// Whether all bytes have been consumed.
  bool get isDone => remaining == 0;

  /// Returns an immutable copy of the original input bytes.
  Uint8List toBytes() => Uint8List.fromList(_bytes).asUnmodifiableView();

  /// Reads a single byte and advances [offset].
  int readByte() {
    _requireAvailable(1);
    final byte = _bytes[_offset];
    _offset += 1;
    return byte;
  }

  /// Reads [count] bytes and advances [offset].
  Uint8List readBytes(int count) {
    RangeError.checkNotNegative(count, 'count');
    _requireAvailable(count);

    final start = _offset;
    _offset += count;
    return Uint8List.fromList(_bytes.sublist(start, _offset))
        .asUnmodifiableView();
  }

  /// Returns the next byte without advancing [offset].
  int peekByte() {
    _requireAvailable(1);
    return _bytes[_offset];
  }

  /// Advances [offset] by [count] bytes.
  void skip(int count) {
    RangeError.checkNotNegative(count, 'count');
    _requireAvailable(count);
    _offset += count;
  }

  void _requireAvailable(int count) {
    if (remaining >= count) {
      return;
    }

    throw TruncatedInputException(
      offset: _offset,
      expected: count,
      remaining: remaining,
    );
  }
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
