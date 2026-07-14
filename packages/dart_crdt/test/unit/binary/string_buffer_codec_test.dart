import 'dart:typed_data';

import 'package:dart_crdt/src/binary/byte_reader.dart';
import 'package:dart_crdt/src/binary/byte_writer.dart';
import 'package:dart_crdt/src/binary/string_buffer_codec.dart';
import 'package:test/test.dart';

void main() {
  group('string codec', () {
    test('round-trips an empty string', () {
      final bytes = _writeString('');

      expect(bytes, [0]);
      expect(readString(ByteReader(bytes)), '');
    });

    test('round-trips ASCII text', () {
      final bytes = _writeString('collaboration');

      expect(bytes.first, 13);
      expect(readString(ByteReader(bytes)), 'collaboration');
    });

    test('round-trips multi-byte Unicode text', () {
      const value = 'Delta Δ café 😀';
      final bytes = _writeString(value);

      expect(bytes.first, greaterThan(value.length));
      expect(readString(ByteReader(bytes)), value);
    });

    test('preserves a leading Unicode BOM as user data', () {
      const value = '\uFEFFpayload';

      expect(readString(ByteReader(_writeString(value))), value);
    });

    test('rejects malformed UTF-8 payloads', () {
      final invalidContinuation = [2, 0xc3, 0x28];
      final overlongEncoding = [2, 0xc0, 0x80];
      final surrogateEncoding = [3, 0xed, 0xa0, 0x80];

      expect(
        () => readString(ByteReader(invalidContinuation)),
        throwsA(isA<MalformedUtf8Exception>()),
      );
      expect(
        () => readString(ByteReader(overlongEncoding)),
        throwsA(isA<MalformedUtf8Exception>()),
      );
      expect(
        () => readString(ByteReader(surrogateEncoding)),
        throwsA(isA<MalformedUtf8Exception>()),
      );
    });

    test('rejects truncated string payloads', () {
      expect(
        () => readString(ByteReader([4, 0x74, 0x65])),
        throwsA(isA<TruncatedInputException>()),
      );
    });
  });

  group('byte buffer codec', () {
    test('round-trips an empty buffer', () {
      final bytes = _writeBuffer(const []);

      expect(bytes, [0]);
      expect(readByteBuffer(ByteReader(bytes)), isEmpty);
    });

    test('round-trips a mutable byte buffer defensively', () {
      final source = Uint8List.fromList([0, 1, 127, 128, 255]);
      final bytes = _writeBuffer(source);
      source[0] = 99;

      final reader = ByteReader(bytes);
      final decoded = readByteBuffer(reader);

      expect(bytes, [5, 0, 1, 127, 128, 255]);
      expect(decoded, [0, 1, 127, 128, 255]);
      expect(() => decoded[0] = 7, throwsUnsupportedError);
      expect(reader.isDone, isTrue);
    });

    test('round-trips a large buffer with a multi-byte length prefix', () {
      final source = Uint8List.fromList([
        for (var index = 0; index < 300; index += 1) index % 256,
      ]);
      final bytes = _writeBuffer(source);

      expect(bytes.take(2), [172, 2]);
      expect(readByteBuffer(ByteReader(bytes)), source);
    });

    test('rejects truncated buffers', () {
      expect(
        () => readByteBuffer(ByteReader([3, 1, 2])),
        throwsA(isA<TruncatedInputException>()),
      );
    });
  });
}

Uint8List _writeString(String value) {
  final writer = ByteWriter();
  writeString(writer, value);
  return writer.toBytes();
}

Uint8List _writeBuffer(List<int> bytes) {
  final writer = ByteWriter();
  writeByteBuffer(writer, bytes);
  return writer.toBytes();
}
