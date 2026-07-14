import 'package:dart_crdt/src/binary/byte_reader.dart';
import 'package:dart_crdt/src/binary/rle_codec.dart';
import 'package:dart_crdt/src/binary/uint_opt_rle_codec.dart';
import 'package:dart_crdt/src/binary/varint_codec.dart';
import 'package:test/test.dart';

void main() {
  group('basic RLE', () {
    test('encodes repeated signed values', () {
      final encoder = RleIntEncoder();

      for (final value in [7, 7, 7, 8, 9, 9]) {
        encoder.write(value);
      }

      final bytes = encoder.toBytes();

      expect(bytes, [7, 2, 8, 0, 9]);
      expect(RleIntDecoder(bytes).readAll(6), [7, 7, 7, 8, 9, 9]);
      expect(() => encoder.write(10), throwsStateError);
    });

    test('encodes alternating unsigned values', () {
      final encoder = UintRleEncoder();

      for (final value in [1, 2, 1]) {
        encoder.write(value);
      }

      final bytes = encoder.toBytes();

      expect(bytes, [1, 0, 2, 0, 1]);
      expect(UintRleDecoder(bytes).readAll(3), [1, 2, 1]);
      expect(() => UintRleEncoder().write(-1), throwsRangeError);
    });

    test('rejects corrupted run counts', () {
      expect(
        () => RleIntDecoder([1, 128]).read(),
        throwsA(isA<TruncatedInputException>()),
      );
      expect(
        () => UintRleDecoder([1, 128]).read(),
        throwsA(isA<TruncatedInputException>()),
      );
    });
  });

  group('integer diff RLE', () {
    test('encodes repeated values and monotonic clocks', () {
      final encoder = IntDiffRleEncoder();

      for (final value in [1, 1, 1, 2, 3, 4]) {
        encoder.write(value);
      }

      final bytes = encoder.toBytes();

      expect(bytes, [1, 2, 1, 0, 1, 0, 1]);
      expect(IntDiffRleDecoder(bytes).readAll(6), [1, 1, 1, 2, 3, 4]);
    });

    test('encodes negative diffs', () {
      final encoder = IntDiffRleEncoder(start: 10);

      for (final value in [8, 8, 6]) {
        encoder.write(value);
      }

      final bytes = encoder.toBytes();

      expect(bytes, [66, 1, 66]);
      expect(IntDiffRleDecoder(bytes, start: 10).readAll(3), [8, 8, 6]);
    });
  });

  group('optimized unsigned RLE', () {
    test('encodes repeated unsigned values', () {
      final encoder = UintOptRleEncoder();

      for (final value in [1, 2, 3, 3, 3]) {
        encoder.write(value);
      }

      final bytes = encoder.toBytes();

      expect(bytes, [1, 2, 67, 1]);
      expect(UintOptRleDecoder(bytes).readAll(5), [1, 2, 3, 3, 3]);
    });

    test('preserves repeated zero runs', () {
      final encoder = UintOptRleEncoder()
        ..write(0)
        ..write(0)
        ..write(0);

      final bytes = encoder.toBytes();

      expect(bytes, [64, 1]);
      expect(UintOptRleDecoder(bytes).readAll(3), [0, 0, 0]);
    });

    test('encodes increasing monotonic runs', () {
      final encoder = IncreasingUintOptRleEncoder();

      for (final value in [7, 8, 9, 10, 1, 3, 5]) {
        encoder.write(value);
      }

      final bytes = encoder.toBytes();

      expect(bytes, [71, 2, 1, 3, 5]);
      expect(
        IncreasingUintOptRleDecoder(bytes).readAll(7),
        [7, 8, 9, 10, 1, 3, 5],
      );
    });

    test('rejects corrupted optimized counts', () {
      expect(
        () => UintOptRleDecoder([64]).read(),
        throwsA(isA<TruncatedInputException>()),
      );
    });
  });

  group('optimized integer diff RLE', () {
    test('encodes repeated positive diffs', () {
      final encoder = IntDiffOptRleEncoder();

      for (final value in [1, 2, 3, 2]) {
        encoder.write(value);
      }

      final bytes = encoder.toBytes();

      expect(bytes, [3, 1, 66]);
      expect(IntDiffOptRleDecoder(bytes).readAll(4), [1, 2, 3, 2]);
    });

    test('encodes repeated negative diffs', () {
      final encoder = IntDiffOptRleEncoder();

      for (final value in [10, 8, 6, 5]) {
        encoder.write(value);
      }

      final bytes = encoder.toBytes();

      expect(bytes, [20, 67, 0, 66]);
      expect(IntDiffOptRleDecoder(bytes).readAll(4), [10, 8, 6, 5]);
    });

    test('rejects corrupted optimized diff counts and varints', () {
      expect(
        () => IntDiffOptRleDecoder([1]).read(),
        throwsA(isA<TruncatedInputException>()),
      );
      expect(
        () => IntDiffOptRleDecoder(List<int>.filled(8, 255)).read(),
        throwsA(isA<MalformedVarintException>()),
      );
    });
  });
}
