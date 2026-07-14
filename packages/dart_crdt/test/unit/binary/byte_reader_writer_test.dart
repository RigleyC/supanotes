import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_crdt/src/binary/byte_reader.dart';
import 'package:dart_crdt/src/binary/byte_writer.dart';
import 'package:test/test.dart';

void main() {
  group('ByteReader', () {
    test('handles empty input', () {
      final reader = ByteReader(_fixtureBytes('empty'));

      expect(reader.length, 0);
      expect(reader.offset, 0);
      expect(reader.remaining, 0);
      expect(reader.isDone, isTrue);
      expect(reader.toBytes(), isEmpty);
      expect(reader.readByte, throwsA(isA<TruncatedInputException>()));
    });

    test('reads a single byte', () {
      final reader = ByteReader(_fixtureBytes('single'));

      expect(reader.peekByte(), 42);
      expect(reader.offset, 0);
      expect(reader.readByte(), 42);
      expect(reader.offset, 1);
      expect(reader.remaining, 0);
      expect(reader.isDone, isTrue);
    });

    test('reads multiple bytes and skip advances offset', () {
      final reader = ByteReader(_fixtureBytes('multi'));

      expect(reader.readByte(), 0);
      expect(reader.readBytes(2), [1, 127]);
      reader.skip(1);
      expect(reader.offset, 4);
      expect(reader.readByte(), 255);
      expect(reader.isDone, isTrue);
    });

    test('returns immutable byte snapshots', () {
      final source = _fixtureBytes('multi');
      final reader = ByteReader(source);
      source[0] = 99;

      final snapshot = reader.toBytes();
      final chunk = reader.readBytes(2);

      expect(snapshot, [0, 1, 127, 128, 255]);
      expect(chunk, [0, 1]);
      expect(() => snapshot[0] = 7, throwsUnsupportedError);
      expect(() => chunk[0] = 7, throwsUnsupportedError);
    });

    test('throws clear exceptions for truncated input', () {
      final reader = ByteReader([1, 2]);
      reader.readByte();

      expect(
        () => reader.readBytes(2),
        throwsA(
          isA<TruncatedInputException>()
              .having((error) => error.offset, 'offset', 1)
              .having((error) => error.expected, 'expected', 2)
              .having((error) => error.remaining, 'remaining', 1)
              .having(
                (error) => error.message,
                'message',
                contains('expected 2 byte(s)'),
              ),
        ),
      );
    });

    test('rejects negative read and skip counts', () {
      final reader = ByteReader(_fixtureBytes('multi'));

      expect(() => reader.readBytes(-1), throwsRangeError);
      expect(() => reader.skip(-1), throwsRangeError);
    });
  });

  group('ByteWriter', () {
    test('starts empty and writes a single byte', () {
      final writer = ByteWriter();

      expect(writer.isEmpty, isTrue);
      expect(writer.length, 0);

      writer.writeByte(42);

      expect(writer.isEmpty, isFalse);
      expect(writer.length, 1);
      expect(writer.toBytes(), [42]);
    });

    test('writes multiple byte chunks', () {
      final writer = ByteWriter()
        ..writeBytes(_fixtureBytes('multi'))
        ..writeByte(3);

      expect(writer.length, 6);
      expect(writer.toBytes(), [0, 1, 127, 128, 255, 3]);
    });

    test('returns immutable output snapshots', () {
      final writer = ByteWriter()..writeBytes([1, 2]);
      final first = writer.toBytes();

      writer.writeByte(3);
      final second = writer.toBytes();

      expect(first, [1, 2]);
      expect(second, [1, 2, 3]);
      expect(() => first[0] = 7, throwsUnsupportedError);
      expect(() => second[0] = 7, throwsUnsupportedError);
    });

    test('rejects out-of-range byte values', () {
      final writer = ByteWriter();

      expect(() => writer.writeByte(-1), throwsRangeError);
      expect(() => writer.writeByte(256), throwsRangeError);
      expect(() => writer.writeBytes([0, 256]), throwsRangeError);
    });

    test('clear removes accumulated bytes', () {
      final writer = ByteWriter()..writeBytes([1, 2, 3]);

      writer.clear();

      expect(writer.isEmpty, isTrue);
      expect(writer.length, 0);
      expect(writer.toBytes(), isEmpty);
    });
  });
}

Uint8List _fixtureBytes(String name) {
  final fixture = _byteFixture();
  final values = fixture[name];
  if (values is! List<Object?>) {
    fail('Missing byte fixture "$name".');
  }

  return Uint8List.fromList([
    for (final value in values) value as int,
  ]);
}

Map<String, Object?> _byteFixture() {
  final file = File('test/fixtures/binary/byte_sequences.json');
  return jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
}
