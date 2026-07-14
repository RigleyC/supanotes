import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_crdt/src/binary/any_codec.dart';
import 'package:dart_crdt/src/binary/any_value.dart';
import 'package:dart_crdt/src/binary/byte_reader.dart';
import 'package:dart_crdt/src/binary/byte_writer.dart';
import 'package:test/test.dart';

void main() {
  group('any-value codec', () {
    for (final fixture in _fixtures()) {
      test('round-trips ${fixture.name}', () {
        final writer = ByteWriter();

        writeAnyValue(writer, fixture.value);

        expect(writer.toBytes(), fixture.bytes);

        final reader = ByteReader(fixture.bytes);
        expect(readAnyValue(reader), fixture.value);
        expect(reader.isDone, isTrue);
      });
    }

    test('defensively copies binary payloads', () {
      final source = Uint8List.fromList([1, 2, 3]);
      final value = AnyBinary(source);
      source[0] = 99;

      final object = value.toObject();

      expect(value.bytes, [1, 2, 3]);
      expect(object, [1, 2, 3]);
      expect(() => object[0] = 7, throwsUnsupportedError);
    });

    test('rejects malformed input', () {
      expect(
        () => readAnyValue(ByteReader([99])),
        throwsA(isA<MalformedAnyValueException>()),
      );
      expect(
        () => readAnyValue(ByteReader([4, 0, 0])),
        throwsA(isA<TruncatedInputException>()),
      );
      expect(
        () => readAnyValue(ByteReader(_nonFiniteDoubleBytes())),
        throwsA(isA<MalformedAnyValueException>()),
      );
    });
  });

  group('typed JSON values', () {
    test('convert supported Dart JSON objects without dynamic values', () {
      final value = JsonValue.fromObject({
        'title': 'doc',
        'items': [
          null,
          true,
          3,
        ],
      });

      expect(
        value.toObject(),
        {
          'title': 'doc',
          'items': [null, true, 3],
        },
      );
    });

    test('round-trips JSON values through the JSON codec', () {
      final value = JsonValue.fromObject({
        'text': 'hello',
        'count': 2,
      });
      final writer = ByteWriter();

      writeJsonValue(writer, value);

      expect(readJsonValue(ByteReader(writer.toBytes())), value);
    });

    test('rejects unsupported objects and invalid JSON numbers', () {
      expect(
        () => AnyValue.fromObject(Object()),
        throwsA(isA<UnsupportedAnyValueException>()),
      );
      expect(
        () => JsonValue.fromObject({1: 'not a string key'}),
        throwsA(isA<UnsupportedAnyValueException>()),
      );
      expect(
        () => JsonNumber(double.nan),
        throwsA(isA<UnsupportedAnyValueException>()),
      );
    });
  });
}

List<_AnyFixture> _fixtures() {
  final file = File('test/fixtures/binary/any_values.json');
  final data = jsonDecode(file.readAsStringSync()) as List<Object?>;
  return [
    for (final item in data) _AnyFixture.fromJson(item as Map<String, Object?>),
  ];
}

List<int> _nonFiniteDoubleBytes() {
  final bytes = ByteData(8)..setFloat64(0, double.infinity, Endian.little);
  return [4, ...bytes.buffer.asUint8List()];
}

final class _AnyFixture {
  const _AnyFixture({
    required this.name,
    required this.value,
    required this.bytes,
  });

  factory _AnyFixture.fromJson(Map<String, Object?> json) {
    return _AnyFixture(
      name: json['name'] as String,
      value: _valueFromJson(json['value'] as Map<String, Object?>),
      bytes: _bytesFromJson(json['bytes']),
    );
  }

  final String name;
  final AnyValue value;
  final List<int> bytes;
}

AnyValue _valueFromJson(Map<String, Object?> json) {
  final kind = json['kind'] as String;
  return switch (kind) {
    'null' => const JsonNull(),
    'bool' => JsonBool(json['value'] as bool),
    'number' => JsonNumber(json['value'] as num),
    'string' => JsonString(json['value'] as String),
    'binary' => AnyBinary(_bytesFromJson(json['bytes'])),
    'list' => AnyList(_listFromJson(json['values'])),
    'map' => AnyMap(_mapFromJson(json['entries'])),
    _ => fail('Unknown fixture value kind "$kind".'),
  };
}

List<AnyValue> _listFromJson(Object? value) {
  final items = value as List<Object?>;
  return [
    for (final item in items) _valueFromJson(item as Map<String, Object?>),
  ];
}

Map<String, AnyValue> _mapFromJson(Object? value) {
  final entries = value as Map<String, Object?>;
  return entries.map((key, value) {
    return MapEntry(key, _valueFromJson(value as Map<String, Object?>));
  });
}

List<int> _bytesFromJson(Object? value) {
  final bytes = value as List<Object?>;
  return [
    for (final byte in bytes) byte as int,
  ];
}
