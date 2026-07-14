import 'dart:convert';
import 'dart:io';

import 'package:dart_crdt/src/binary/byte_reader.dart';
import 'package:dart_crdt/src/binary/byte_writer.dart';
import 'package:dart_crdt/src/binary/varint_codec.dart';
import 'package:test/test.dart';

void main() {
  group('unsigned varint', () {
    for (final fixture in _fixtures('unsigned')) {
      test('round-trips ${fixture.value}', () {
        final writer = ByteWriter();

        writeVarUint(writer, fixture.value);

        expect(writer.toBytes(), fixture.bytes);

        final reader = ByteReader(fixture.bytes);
        expect(readVarUint(reader), fixture.value);
        expect(reader.isDone, isTrue);
      });
    }

    test('rejects values outside the portable integer range', () {
      final writer = ByteWriter();

      expect(() => writeVarUint(writer, -1), throwsRangeError);
      expect(
        () => writeVarUint(writer, maxSafeInteger + 1),
        throwsRangeError,
      );
    });

    test('rejects malformed continuation bytes', () {
      final tooLong = List<int>.filled(8, 255);
      final overflow = [255, 255, 255, 255, 255, 255, 255, 16];

      expect(
        () => readVarUint(ByteReader(tooLong)),
        throwsA(isA<MalformedVarintException>()),
      );
      expect(
        () => readVarUint(ByteReader(overflow)),
        throwsA(isA<MalformedVarintException>()),
      );
      expect(
        () => readVarUint(ByteReader([128])),
        throwsA(isA<TruncatedInputException>()),
      );
    });
  });

  group('signed varint', () {
    for (final fixture in _fixtures('signed')) {
      test('round-trips ${fixture.value}', () {
        final writer = ByteWriter();

        writeVarInt(writer, fixture.value);

        expect(writer.toBytes(), fixture.bytes);

        final reader = ByteReader(fixture.bytes);
        expect(readVarInt(reader), fixture.value);
        expect(reader.isDone, isTrue);
      });
    }

    test('rejects values outside the portable integer range', () {
      final writer = ByteWriter();

      expect(
        () => writeVarInt(writer, maxSafeInteger + 1),
        throwsRangeError,
      );
      expect(
        () => writeVarInt(writer, -maxSafeInteger - 1),
        throwsRangeError,
      );
    });

    test('rejects malformed continuation bytes', () {
      final tooLong = List<int>.filled(8, 255);
      final overflow = [191, 255, 255, 255, 255, 255, 255, 32];

      expect(
        () => readVarInt(ByteReader(tooLong)),
        throwsA(isA<MalformedVarintException>()),
      );
      expect(
        () => readVarInt(ByteReader(overflow)),
        throwsA(isA<MalformedVarintException>()),
      );
      expect(
        () => readVarInt(ByteReader([128])),
        throwsA(isA<TruncatedInputException>()),
      );
    });
  });
}

List<_VarintFixture> _fixtures(String groupName) {
  final values = _fixtureData()[groupName];
  if (values is! List<Object?>) {
    fail('Missing varint fixture group "$groupName".');
  }

  return [
    for (final value in values)
      _VarintFixture.fromJson(value as Map<String, Object?>),
  ];
}

Map<String, Object?> _fixtureData() {
  final file = File('test/fixtures/binary/varints.json');
  return jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
}

final class _VarintFixture {
  const _VarintFixture({
    required this.value,
    required this.bytes,
  });

  factory _VarintFixture.fromJson(Map<String, Object?> json) {
    final bytes = json['bytes'];
    if (bytes is! List<Object?>) {
      fail('Fixture is missing byte data.');
    }

    return _VarintFixture(
      value: json['value'] as int,
      bytes: [
        for (final byte in bytes) byte as int,
      ],
    );
  }

  final int value;
  final List<int> bytes;
}
