import 'dart:convert';
import 'dart:io';

import 'package:dart_crdt/dart_crdt.dart';
import 'package:test/test.dart';

const _fixturePath =
    'test/fixtures/relative_position/relative_position_codecs.json';

void main() {
  group('RelativePosition JSON and binary codecs', () {
    test('round-trips fixture variants', () {
      final fixtures = _loadFixtures();

      for (final entry in fixtures.entries) {
        final json = _objectMap(entry.value['json'], entry.key);
        final bytes = _decodeHex(_stringField(entry.value, 'bytesHex'));
        final position = RelativePosition.fromJson(json);

        expect(position.toJson(), json, reason: entry.key);
        expect(_hex(encodeRelativePosition(position)), _hex(bytes));
        expect(decodeRelativePosition(bytes), position);
      }
    });

    test('compares relative positions by anchor and assoc', () {
      final item = RelativePosition.item(_id(1, 2));
      final sameItem = RelativePosition.fromJson(item.toJson());
      final root = RelativePosition.root('body', assoc: -1);
      final sorted = [root, item]..sort();

      expect(compareRelativePositions(item, sameItem), isTrue);
      expect(compareRelativePositions(item, root), isFalse);
      expect(compareRelativePositions(null, null), isTrue);
      expect(compareRelativePositions(item, null), isFalse);
      expect(sorted, [item, root]);
      expect(decodeRelativePosition(const [1, 0]), RelativePosition.root(''));
    });

    test('compares absolute positions by shared type identity', () {
      final type = SharedType(kind: SharedTypeKind.text, name: 'body');
      final same = AbsolutePosition(type: type, index: 3, assoc: -1);
      final equal = AbsolutePosition(type: type, index: 3, assoc: -1);
      final otherType = SharedType(kind: SharedTypeKind.text, name: 'body');

      expect(same, equal);
      expect(
        same,
        isNot(AbsolutePosition(type: otherType, index: 3, assoc: -1)),
      );
      expect(() => AbsolutePosition(type: type, index: -1), throwsRangeError);
    });

    test('rejects malformed JSON payloads', () {
      expect(() => RelativePosition.fromJson(const {}), throwsArgumentError);
      expect(
        () => RelativePosition.fromJson({
          'item': {'client': 1},
        }),
        throwsA(isA<MalformedRelativePositionException>()),
      );
      expect(
        () => RelativePosition.fromJson({'tname': 7}),
        throwsA(isA<MalformedRelativePositionException>()),
      );
      expect(
        () => RelativePosition.fromJson({'tname': 'body', 'assoc': 1.5}),
        throwsA(isA<MalformedRelativePositionException>()),
      );
    });

    test('rejects malformed binary payloads', () {
      expect(() => decodeRelativePosition(const []), throwsException);
      expect(
        () => decodeRelativePosition(const [9, 0]),
        throwsA(isA<MalformedRelativePositionException>()),
      );
      expect(
        () => decodeRelativePosition(const [1, 0, 0, 99]),
        throwsA(isA<MalformedRelativePositionException>()),
      );
    });
  });
}

Map<String, Map<String, Object?>> _loadFixtures() {
  final decoded = jsonDecode(File(_fixturePath).readAsStringSync());
  final fixture = _objectMap(decoded, _fixturePath);
  return {
    for (final entry in fixture.entries)
      entry.key: _objectMap(entry.value, entry.key),
  };
}

Id _id(int client, int clock) {
  return Id(client: ClientId(client), clock: Clock(clock));
}

List<int> _decodeHex(String value) {
  if (value.length.isOdd) {
    throw StateError('Odd hex payload length.');
  }
  return [
    for (var index = 0; index < value.length; index += 2)
      int.parse(value.substring(index, index + 2), radix: 16),
  ];
}

String _hex(List<int> bytes) {
  return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}

Map<String, Object?> _objectMap(Object? value, String context) {
  if (value is Map<String, Object?>) {
    return value;
  }
  throw StateError('$context must be an object.');
}

String _stringField(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is String) {
    return field;
  }
  throw StateError('$key must be a string.');
}
