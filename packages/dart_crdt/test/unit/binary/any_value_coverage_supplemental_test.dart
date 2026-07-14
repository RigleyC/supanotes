import 'dart:typed_data';

import 'package:dart_crdt/src/binary/any_value.dart';
import 'package:test/test.dart';

void main() {
  group('any-value supplemental coverage', () {
    test('converts binary-capable Dart values and covers container identity',
        () {
      final binary = AnyValue.fromObject(Uint8List.fromList([1, 2]));
      final list = AnyValue.fromObject([
        Uint8List.fromList([3]),
        {'k': true},
      ]);
      final map = AnyValue.fromObject({
        'bytes': Uint8List.fromList([4]),
        'items': [1],
      });
      final jsonList = JsonValue.fromObject([
        {'a': 1},
      ]);
      final jsonMap = JsonValue.fromObject({
        'a': [true],
      });

      expect(binary, AnyBinary([1, 2]));
      expect(list.toObject(), [
        Uint8List.fromList([3]),
        {'k': true},
      ]);
      expect(map.toObject(), {
        'bytes': Uint8List.fromList([4]),
        'items': [1],
      });
      expect(
        jsonList.hashCode,
        JsonValue.fromObject([
          {'a': 1},
        ]).hashCode,
      );
      expect(
        jsonList,
        JsonValue.fromObject([
          {'a': 1},
        ]),
      );
      expect(
        jsonMap.hashCode,
        JsonValue.fromObject({
          'a': [true],
        }).hashCode,
      );
      expect(
        AnyList([binary]),
        AnyList([
          AnyBinary([1, 2]),
        ]),
      );
      expect(
        AnyList([binary]).hashCode,
        AnyList([
          AnyBinary([1, 2]),
        ]).hashCode,
      );
      expect(
        AnyMap({'b': binary}),
        AnyMap({
          'b': AnyBinary([1, 2]),
        }),
      );
      expect(AnyMap({'b': binary}).hashCode, AnyMap({'b': binary}).hashCode);
      expect(AnyBinary([1, 2]).hashCode, AnyBinary([1, 2]).hashCode);
      expect(AnyBinary([1, 2]) == AnyBinary([2, 1]), isFalse);
      expect(() => AnyBinary([300]), throwsRangeError);
    });
  });
}
