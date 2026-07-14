import 'package:dart_crdt/src/content/content.dart';
import 'package:dart_crdt/src/doc/doc.dart';
import 'package:dart_crdt/src/relative_position/relative_position.dart';
import 'package:dart_crdt/src/structs/id.dart';
import 'package:test/test.dart';

void main() {
  group('relative position value supplemental coverage', () {
    test('covers value ordering, JSON aliases, identity, and diagnostics', () {
      final item = RelativePosition.item(_id(1, 2), assoc: -1);
      final sameItem = RelativePosition.fromJson(item.toJson());
      final type = RelativePosition.type(_id(1, 3), assoc: 1);
      final root = RelativePosition.fromJson({'rootName': 'body'});
      const malformed = MalformedRelativePositionException(
        offset: 2,
        reason: 'bad',
        source: 'input',
      );

      expect(item, sameItem);
      expect(item.hashCode, sameItem.hashCode);
      expect(item.toString(), contains('RelativePosition'));
      expect(type.compareTo(item) == 0, isFalse);
      expect(root, RelativePosition.root('body'));
      expect(compareRelativePositions(null, root), isFalse);
      expect(malformed.source, 'input');
      expect(malformed.toString(), contains(malformed.message));
      expect(RelativePosition.new, throwsArgumentError);
      expect(
        () => RelativePosition.root('x', assoc: 9007199254740992),
        throwsRangeError,
      );
      expect(
        () => RelativePosition.fromJson({'item': 'bad'}),
        throwsA(isA<MalformedRelativePositionException>()),
      );
      expect(
        () => RelativePosition.fromJson({
          'item': {'client': 'bad', 'clock': 1},
        }),
        throwsA(isA<MalformedRelativePositionException>()),
      );
    });

    test('covers absolute position identity and diagnostics', () {
      final type = SharedType(kind: SharedTypeKind.text, name: 'body');
      final absolute = AbsolutePosition(type: type, index: 1, assoc: -1);

      expect(absolute, AbsolutePosition(type: type, index: 1, assoc: -1));
      expect(
        absolute.hashCode,
        AbsolutePosition(type: type, index: 1, assoc: -1).hashCode,
      );
      expect(absolute.toString(), contains('body'));
      expect(
        absolute ==
            AbsolutePosition(
              type: SharedType(kind: SharedTypeKind.text),
              index: 1,
            ),
        isFalse,
      );
      expect(() => AbsolutePosition(type: type, index: -1), throwsRangeError);
    });
  });
}

Id _id(int client, int clock) {
  return Id(client: ClientId(client), clock: Clock(clock));
}
