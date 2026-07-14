import 'package:dart_crdt/src/binary/byte_reader.dart';
import 'package:dart_crdt/src/binary/string_table.dart';
import 'package:test/test.dart';

void main() {
  group('StringTableEncoder', () {
    test('deduplicates repeated property keys', () {
      final encoder = StringTableEncoder();

      expect(encoder.write('type'), 0);
      expect(encoder.write('name'), 1);
      expect(encoder.write('type'), 0);
      expect(encoder.write('type'), 0);

      final bytes = encoder.toBytes();

      expect(encoder.length, 2);
      expect(encoder.referenceCount, 4);
      expect(encoder.strings, ['type', 'name']);
      expect(bytes, [
        2,
        4,
        116,
        121,
        112,
        101,
        4,
        110,
        97,
        109,
        101,
        4,
        0,
        1,
        0,
        0,
      ]);

      final decoder = StringTableDecoder(bytes);
      expect(decoder.strings, ['type', 'name']);
      expect(decoder.readAll(4), ['type', 'name', 'type', 'type']);
      expect(decoder.isDone, isTrue);
    });

    test('preserves insertion order for unique strings', () {
      final encoder = StringTableEncoder()
        ..write('z')
        ..write('a')
        ..write('z')
        ..write('b');

      final decoder = StringTableDecoder(encoder.toBytes());

      expect(encoder.strings, ['z', 'a', 'b']);
      expect(decoder.strings, ['z', 'a', 'b']);
      expect(decoder.readAll(4), ['z', 'a', 'z', 'b']);
    });

    test('handles empty keys', () {
      final encoder = StringTableEncoder()
        ..write('')
        ..write('');

      final bytes = encoder.toBytes();

      expect(encoder.strings, ['']);
      expect(bytes, [1, 0, 2, 0, 0]);
      expect(StringTableDecoder(bytes).readAll(2), ['', '']);
    });

    test('handles multi-byte keys and content strings', () {
      final values = ['Δ', 'emoji 😀', 'Δ', 'café'];
      final encoder = StringTableEncoder();

      for (final value in values) {
        encoder.write(value);
      }

      final decoder = StringTableDecoder(encoder.toBytes());

      expect(decoder.strings, ['Δ', 'emoji 😀', 'café']);
      expect(decoder.readAll(values.length), values);
    });

    test('does not leak mutable table internals', () {
      final encoder = StringTableEncoder()..write('key');
      final strings = encoder.strings;
      final bytes = encoder.toBytes();
      final decoder = StringTableDecoder(bytes);

      expect(() => strings.add('mutated'), throwsUnsupportedError);
      expect(() => decoder.strings.add('mutated'), throwsUnsupportedError);
      expect(() => bytes[0] = 99, throwsUnsupportedError);
      expect(() => encoder.write('later'), throwsStateError);
    });
  });

  group('StringTableDecoder', () {
    test('throws when references are exhausted', () {
      final decoder =
          StringTableDecoder((StringTableEncoder()..write('x')).toBytes());

      expect(decoder.read(), 'x');
      expect(decoder.remainingReferences, 0);
      expect(decoder.read, throwsA(isA<StringTableExhaustedException>()));
    });

    test('rejects invalid string ids', () {
      final bytes = [1, 3, 111, 110, 101, 1, 1];
      final decoder = StringTableDecoder(bytes);

      expect(
        decoder.read,
        throwsA(isA<MalformedStringTableException>()),
      );
    });

    test('rejects truncated reference streams', () {
      final bytes = [1, 1, 97, 1, 128];
      final decoder = StringTableDecoder(bytes);

      expect(
        decoder.read,
        throwsA(isA<TruncatedInputException>()),
      );
    });
  });
}
