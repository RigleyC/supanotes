import 'dart:typed_data';

import 'package:dart_crdt/src/binary/any_codec.dart';
import 'package:dart_crdt/src/binary/any_value.dart';
import 'package:dart_crdt/src/binary/byte_reader.dart';
import 'package:dart_crdt/src/binary/byte_writer.dart';
import 'package:dart_crdt/src/binary/string_buffer_codec.dart';
import 'package:dart_crdt/src/binary/string_table.dart';
import 'package:dart_crdt/src/binary/uint_opt_rle_codec.dart';
import 'package:dart_crdt/src/binary/varint_codec.dart';
import 'package:test/test.dart';

void main() {
  group('strict binary codec coverage', () {
    test('covers exception diagnostics and JSON conversion errors', () {
      final any = const MalformedAnyValueException(
        offset: 2,
        reason: 'bad',
      );
      final utf8Error = const MalformedUtf8Exception(
        offset: 1,
        reason: 'bad',
      );
      final truncated = const TruncatedInputException(
        offset: 0,
        expected: 4,
        remaining: 1,
      );
      final varint = const MalformedVarintException(
        offset: 3,
        reason: 'bad',
      );
      final exhausted = const StringTableExhaustedException();
      final table = const MalformedStringTableException(
        offset: 4,
        reason: 'bad',
      );

      expect(any.source, isNull);
      expect(any.toString(), contains(any.message));
      expect(utf8Error.source, isNull);
      expect(utf8Error.toString(), contains(utf8Error.message));
      expect(truncated.toString(), contains(truncated.message));
      expect(varint.toString(), contains(varint.message));
      expect(exhausted.toString(), contains(exhausted.message));
      expect(table.source, isNull);
      expect(table.toString(), contains(table.message));

      final writer = ByteWriter();
      writeAnyValue(writer, AnyBinary([1]));
      expect(
        () => readJsonValue(ByteReader(writer.toBytes())),
        throwsA(isA<MalformedAnyValueException>()),
      );
    });

    test('covers strict UTF-8 width and continuation failures', () {
      for (final bytes in const <List<int>>[
        [1, 0xc2],
        [2, 0xe0, 0xa0],
        [3, 0xf0, 0x90, 0x80],
        [2, 0xc2, 0x20],
        [3, 0xe0, 0x80, 0x80],
        [4, 0xf4, 0x90, 0x80, 0x80],
      ]) {
        expect(
          () => readString(ByteReader(bytes)),
          throwsA(isA<MalformedUtf8Exception>()),
        );
      }
    });

    test('covers string table closure and malformed references', () {
      final encoder = StringTableEncoder();
      expect(encoder.intern('a'), 0);
      expect(encoder.write('a'), 0);
      final bytes = encoder.toBytes();

      expect(encoder.toBytes(), bytes);
      expect(() => encoder.write('b'), throwsStateError);

      final decoder = StringTableDecoder(bytes);
      expect(decoder.read(), 'a');
      expect(decoder.read, throwsA(isA<StringTableExhaustedException>()));
      expect(
        () => StringTableDecoder([1, 1, 97, 1, 1]).read(),
        throwsA(isA<MalformedStringTableException>()),
      );
    });

    test('covers optimized RLE closure, readAll, and malformed input', () {
      final unsigned = UintOptRleEncoder()
        ..write(4)
        ..write(4);
      final increasing = IncreasingUintOptRleEncoder()
        ..write(7)
        ..write(8);
      final diffs = IntDiffOptRleEncoder()
        ..write(2)
        ..write(4);

      _expectClosed(unsigned.toBytes, () => unsigned.write(5));
      _expectClosed(increasing.toBytes, () => increasing.write(10));
      _expectClosed(diffs.toBytes, () => diffs.write(9));

      expect(UintOptRleDecoder(unsigned.toBytes()).readAll(2), [4, 4]);
      expect(
        IncreasingUintOptRleDecoder(increasing.toBytes()).readAll(2),
        [7, 8],
      );
      expect(IntDiffOptRleDecoder(diffs.toBytes()).readAll(2), [2, 4]);
      expect(
        () => UintOptRleDecoder(const <int>[]).readAll(-1),
        throwsRangeError,
      );
      expect(
        () => UintOptRleDecoder(List<int>.filled(8, 0x80)).read(),
        throwsA(isA<MalformedVarintException>()),
      );
      expect(
        () => IncreasingUintOptRleDecoder(List<int>.filled(8, 0xff)).read(),
        throwsA(isA<MalformedVarintException>()),
      );
    });

    test('covers binary value object branches', () {
      final writer = ByteWriter();
      final list = AnyList([const JsonString('x')]);
      final map = AnyMap({'k': const JsonBool(true)});
      final binary = AnyBinary(Uint8List.fromList([1, 2]));
      final unsupported = const UnsupportedAnyValueException(
        value: Object(),
        reason: 'bad',
      );

      writeJsonValue(writer, JsonList([const JsonString('x')]));

      expect(list.toObject(), ['x']);
      expect(map.toObject(), {'k': true});
      expect(binary.bytes, [1, 2]);
      expect(readJsonValue(ByteReader(writer.toBytes())).toObject(), ['x']);
      expect(unsupported.toString(), contains(unsupported.message));
      expect(
        () => writeAnyValue(ByteWriter(), JsonNumber(double.infinity)),
        throwsA(isA<UnsupportedAnyValueException>()),
      );
    });
  });
}

void _expectClosed(List<int> Function() toBytes, void Function() write) {
  final bytes = toBytes();
  expect(toBytes(), bytes);
  expect(write, throwsStateError);
}
