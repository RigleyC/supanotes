import 'package:dart_crdt/src/binary/byte_reader.dart';
import 'package:dart_crdt/src/binary/byte_writer.dart';
import 'package:dart_crdt/src/binary/varint_codec.dart';
import 'package:dart_crdt/src/structs/id.dart';
import 'package:test/test.dart';

void main() {
  group('ClientId', () {
    test('validates the portable 53-bit range', () {
      expect(ClientId(0).value, 0);
      expect(ClientId(maxSafeInteger).value, maxSafeInteger);
      expect(() => ClientId(-1), throwsRangeError);
      expect(() => ClientId(maxSafeInteger + 1), throwsRangeError);
    });

    test('compares and writes binary values', () {
      final lower = ClientId(7);
      final higher = ClientId(9);
      final writer = ByteWriter();

      writeClientId(writer, higher);

      expect(lower.compareTo(higher), isNegative);
      expect(higher.compareTo(lower), isPositive);
      expect(readClientId(ByteReader(writer.toBytes())), higher);
    });
  });

  group('Clock', () {
    test('validates non-negative clocks', () {
      expect(Clock(0).value, 0);
      expect(Clock(maxSafeInteger).value, maxSafeInteger);
      expect(() => Clock(-1), throwsRangeError);
      expect(() => Clock(maxSafeInteger + 1), throwsRangeError);
    });

    test('advances and compares clocks', () {
      final clock = Clock(10);
      final advanced = clock.advance(5);

      expect(advanced.value, 15);
      expect(clock.compareTo(advanced), isNegative);
      expect(() => clock.advance(-1), throwsRangeError);
    });
  });

  group('Id', () {
    test('implements equality, hashCode, and stable JSON output', () {
      final first = Id(client: ClientId(1), clock: Clock(2));
      final equal = Id(client: ClientId(1), clock: Clock(2));
      final different = Id(client: ClientId(1), clock: Clock(3));

      expect(first, equal);
      expect(first.hashCode, equal.hashCode);
      expect(first, isNot(different));
      expect(first.toJson(), {'client': 1, 'clock': 2});
      expect(first.toString(), '1:2');
    });

    test('sorts by client then clock', () {
      final ids = [
        Id(client: ClientId(2), clock: Clock(0)),
        Id(client: ClientId(1), clock: Clock(3)),
        Id(client: ClientId(1), clock: Clock(1)),
      ]..sort();

      expect(ids.map((id) => id.toString()), ['1:1', '1:3', '2:0']);
    });

    test('checks same-client identity and clock advancement', () {
      final id = Id(client: ClientId(4), clock: Clock(8));

      expect(
        id.hasSameClient(Id(client: ClientId(4), clock: Clock(10))),
        isTrue,
      );
      expect(
        id.hasSameClient(Id(client: ClientId(5), clock: Clock(8))),
        isFalse,
      );
      expect(id.advance(2), Id(client: ClientId(4), clock: Clock(10)));
    });

    test('round-trips binary client and clock fields', () {
      final id = Id(client: ClientId(150), clock: Clock(300));
      final writer = ByteWriter();

      id.write(writer);

      expect(writer.toBytes(), [150, 1, 172, 2]);
      expect(Id.read(ByteReader(writer.toBytes())), id);
    });

    test('rejects truncated binary ids', () {
      expect(
        () => Id.read(ByteReader([1])),
        throwsA(isA<TruncatedInputException>()),
      );
    });
  });

  group('RootKeyLookup placeholder', () {
    test('describes root id/key lookup without exposing mutable state', () {
      final rootId = Id(client: ClientId(1), clock: Clock(0));
      final lookup = _RootLookup({'shared': rootId});

      expect(lookup.idForKey('shared'), rootId);
      expect(lookup.keyForId(rootId), 'shared');
      expect(lookup.idForKey('missing'), isNull);
      expect(lookup.keyForId(Id(client: ClientId(2), clock: Clock(0))), isNull);
      expect(() => lookup.entries['other'] = rootId, throwsUnsupportedError);
    });

    test('round-trips root key binary placeholders', () {
      final writer = ByteWriter();

      writeRootKey(writer, 'shared-Δ');

      expect(readRootKey(ByteReader(writer.toBytes())), 'shared-Δ');
    });
  });
}

final class _RootLookup implements RootKeyLookup {
  _RootLookup(Map<String, Id> entries) : entries = Map.unmodifiable(entries);

  final Map<String, Id> entries;

  @override
  Id? idForKey(String key) => entries[key];

  @override
  String? keyForId(Id id) {
    for (final entry in entries.entries) {
      if (entry.value == id) {
        return entry.key;
      }
    }
    return null;
  }
}
