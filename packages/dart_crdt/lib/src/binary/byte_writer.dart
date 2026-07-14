/// Bounds-checked byte writer primitives for binary codecs.
library;

import 'dart:typed_data';

/// Appends byte values and returns immutable binary output snapshots.
final class ByteWriter {
  /// Creates an empty byte writer.
  ByteWriter() : _builder = BytesBuilder();

  final BytesBuilder _builder;
  int _length = 0;

  /// The number of bytes written so far.
  int get length => _length;

  /// Whether no bytes have been written.
  bool get isEmpty => _length == 0;

  /// Writes a single byte.
  void writeByte(int byte) {
    RangeError.checkValueInInterval(byte, 0, 255, 'byte');
    _builder.addByte(byte);
    _length += 1;
  }

  /// Writes all bytes from [bytes].
  void writeBytes(List<int> bytes) {
    if (bytes.isEmpty) {
      return;
    }

    final copy = _copyBytes(bytes);
    _builder.add(copy);
    _length += copy.length;
  }

  /// Clears all accumulated bytes.
  void clear() {
    _builder.clear();
    _length = 0;
  }

  /// Returns an immutable copy of the accumulated bytes.
  Uint8List toBytes() => _builder.toBytes().asUnmodifiableView();
}

Uint8List _copyBytes(List<int> bytes) {
  final copy = Uint8List(bytes.length);
  for (var index = 0; index < bytes.length; index += 1) {
    final byte = bytes[index];
    RangeError.checkValueInInterval(byte, 0, 255, 'bytes[$index]');
    copy[index] = byte;
  }
  return copy;
}
