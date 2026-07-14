import 'package:dart_crdt/src/binary/any_value.dart';
import 'package:dart_crdt/src/delta/delta_operation.dart';
import 'package:test/test.dart';

void main() {
  group('DeltaBuilder', () {
    test('appends operations and produces immutable deltas', () {
      final builder = DeltaBuilder()
        ..insertText(
          text: 'Hello',
          attributes: DeltaAttributes.fromJson({'bold': true}),
        )
        ..retain(length: 1)
        ..insertObjects([' ', 'world'])
        ..delete(2)
        ..setAttribute(key: 'title', value: 'Greeting');
      final delta = builder.done();

      builder.insertText(text: '!');

      expect(delta.operations, [
        DeltaInsertText(
          text: 'Hello',
          attributes: DeltaAttributes.fromJson({'bold': true}),
        ),
        DeltaRetain(length: 1),
        DeltaInsertListContent.fromObjects([' ', 'world']),
        DeltaDelete(2),
        DeltaSetAttribute(key: 'title', value: 'Greeting'),
      ]);
      expect(delta.length, 10);
      expect(delta.attributeOperations, [
        DeltaSetAttribute(key: 'title', value: 'Greeting'),
      ]);
      expect(delta.contentOperations.length, 4);
      expect(
        () => delta.operations.add(DeltaDelete(1)),
        throwsUnsupportedError,
      );
    });

    test('supports explicit append, clear, and value insertion', () {
      final builder = DeltaBuilder()
        ..append(DeltaRetain(length: 2))
        ..insertValues([const JsonString('x')]);

      expect(builder.isNotEmpty, isTrue);
      expect(builder.operations, [
        DeltaRetain(length: 2),
        DeltaInsertListContent([const JsonString('x')]),
      ]);

      builder.clear();

      expect(builder.isEmpty, isTrue);
      expect(builder.done(), Delta());
    });
  });

  group('Delta', () {
    test('implements equality, debug rendering, and toBuilder snapshots', () {
      final delta = Delta([
        DeltaInsertText(text: 'a'),
        DeltaRetain(length: 1),
      ]);
      final copy = delta.toBuilder()..delete(1);

      expect(
        delta,
        Delta([DeltaInsertText(text: 'a'), DeltaRetain(length: 1)]),
      );
      expect(
        delta.hashCode,
        Delta([
          DeltaInsertText(text: 'a'),
          DeltaRetain(length: 1),
        ]).hashCode,
      );
      expect(delta.toJson(), {
        'ops': [
          {'insert': 'a'},
          {'retain': 1},
        ],
      });
      expect(delta.toDebugString(), delta.toJson().toString());
      expect(copy.done().operations.last, DeltaDelete(1));
      expect(delta.operations.length, 2);
    });

    test('separates attribute and content operations', () {
      final delta = Delta([
        DeltaSetAttribute(key: 'name', value: 'root'),
        DeltaInsertText(text: 'x'),
        DeltaDeleteAttribute('name'),
      ]);

      expect(delta.contentOperations, [DeltaInsertText(text: 'x')]);
      expect(delta.attributeOperations, [
        DeltaSetAttribute(key: 'name', value: 'root'),
        DeltaDeleteAttribute('name'),
      ]);
      expect(delta.isNotEmpty, isTrue);
      expect(Delta().isEmpty, isTrue);
    });
  });

  group('Deep and attributed delta support', () {
    test('builds nested child and attribute modifications', () {
      final child = DeltaBuilder()..insertText(text: 'nested');
      final parent = DeltaBuilder()
        ..modifyChild(delta: child.done())
        ..modifyAttribute(key: 'meta', delta: child.done());
      final delta = parent.done();

      expect(delta.toJson(), {
        'ops': [
          {
            'modify': [
              {'insert': 'nested'},
            ],
          },
          {
            'modifyAttribute': 'meta',
            'delta': [
              {'insert': 'nested'},
            ],
          },
        ],
      });
      expect(delta.length, 1);
    });

    test('captures insert, delete, and formatting attributions', () {
      final delta = Delta([DeltaInsertText(text: 'x')]);
      final attributed = AttributedDelta(
        delta: delta,
        insertions: [DeltaAttribution(key: 'by', value: 'alice')],
        deletions: [DeltaAttribution(key: 'at', value: 1)],
        formatting: [DeltaAttribution(key: 'formatBy', value: 'bob')],
      );

      expect(attributed.isUnattributed, isFalse);
      expect(attributed.toJson(), {
        'delta': {
          'ops': [
            {'insert': 'x'},
          ],
        },
        'insertions': [
          {'key': 'by', 'value': 'alice'},
        ],
        'deletions': [
          {'key': 'at', 'value': 1},
        ],
        'formatting': [
          {'key': 'formatBy', 'value': 'bob'},
        ],
      });
      expect(
        attributed,
        AttributedDelta(
          delta: delta,
          insertions: [DeltaAttribution(key: 'by', value: 'alice')],
          deletions: [DeltaAttribution(key: 'at', value: 1)],
          formatting: [DeltaAttribution(key: 'formatBy', value: 'bob')],
        ),
      );
    });

    test('detects unattributed completed deltas', () {
      final attributed = AttributedDelta(delta: Delta());

      expect(attributed.isUnattributed, isTrue);
      expect(attributed.toJson(), {
        'delta': {'ops': <Map<String, Object?>>[]},
      });
    });
  });
}
