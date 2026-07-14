import 'package:dart_crdt/src/delta/delta_operation.dart';
import 'package:test/test.dart';

void main() {
  group('delta supplemental coverage', () {
    test('partitions content and attribute operations with stable identity',
        () {
      final insert = DeltaInsertText(text: 'a');
      final set = DeltaSetAttribute(key: 'title', value: 'A');
      final delta = Delta([insert, DeltaRetain(length: 2), set]);

      expect(Delta().isEmpty, isTrue);
      expect(delta.isNotEmpty, isTrue);
      expect(delta.length, 3);
      expect(delta.contentOperations, [insert, DeltaRetain(length: 2)]);
      expect(delta.attributeOperations, [set]);
      expect(delta.toBuilder().done(), delta);
      expect(
        (DeltaBuilder()..deleteAttribute('gone')).done().attributeOperations,
        [DeltaDeleteAttribute('gone')],
      );
      expect(
        delta.hashCode,
        Delta([insert, DeltaRetain(length: 2), set]).hashCode,
      );
      expect(delta.toString(), delta.toDebugString());
    });

    test('covers operation equality and hash branches', () {
      final attrs = DeltaAttributes.fromJson({'bold': true});
      final modifiedAttrs = DeltaAttributes([
        DeltaAttributeModify(
          key: 'comment',
          operations: [DeltaInsertText(text: 'note')],
        ),
      ]);
      final operations = <DeltaOperation>[
        DeltaInsertText(text: 'x', attributes: attrs),
        DeltaInsertListContent.fromObjects(['x'], attributes: attrs),
        DeltaRetain(length: 1, attributes: attrs),
        DeltaDelete(1),
        DeltaModifyChild(
          operations: [DeltaRetain(length: 1)],
          attributes: attrs,
        ),
        DeltaSetAttribute(key: 'title', value: 'A'),
        DeltaDeleteAttribute('title'),
        DeltaModifyAttribute(
          key: 'child',
          operations: [DeltaInsertText(text: 'nested')],
        ),
      ];

      for (final operation in operations) {
        expect(operation, operation);
        expect(operation.hashCode, operation.hashCode);
        expect(operation.toJson(), isNotEmpty);
      }
      expect(modifiedAttrs, DeltaAttributes(modifiedAttrs.changes));
      expect(
        modifiedAttrs.hashCode,
        DeltaAttributes(modifiedAttrs.changes).hashCode,
      );
      expect(
        DeltaAttributeSet(key: 'bold', value: true),
        isNot(DeltaAttributeSet(key: 'italic', value: true)),
      );
      expect(
        DeltaAttributeDelete('bold'),
        isNot(DeltaAttributeDelete('italic')),
      );
      expect(
        DeltaAttributeDelete('bold').hashCode,
        Object.hash('bold', null),
      );
      expect(
        DeltaAttributeModify(
          key: 'comment',
          operations: [DeltaInsertText(text: 'note')],
        ),
        isNot(
          DeltaAttributeModify(
            key: 'comment',
            operations: [DeltaRetain(length: 1)],
          ),
        ),
      );
      expect(
        DeltaModifyChild(operations: [DeltaRetain(length: 1)]),
        isNot(DeltaModifyChild(operations: [DeltaDelete(1)])),
      );
      expect(
        DeltaDeleteAttribute('title').hashCode,
        Object.hash('title', null),
      );
      expect(DeltaDeleteAttribute('title').length, 0);
      expect(
        DeltaModifyAttribute(
          key: 'child',
          operations: [DeltaInsertText(text: 'nested')],
        ).length,
        0,
      );
    });

    test('covers attributed delta JSON and identity branches', () {
      final attribution = DeltaAttribution(key: 'author', value: 'Ada');
      final otherAttribution = DeltaAttribution(key: 'author', value: 'Bob');
      final attributed = AttributedDelta(
        delta: Delta([DeltaInsertText(text: 'x')]),
        insertions: [attribution],
        deletions: [otherAttribution],
        formatting: [DeltaAttribution(key: 'format', value: true)],
      );

      expect(AttributedDelta(delta: Delta()).isUnattributed, isTrue);
      expect(attribution.toJson(), {'key': 'author', 'value': 'Ada'});
      expect(attribution, DeltaAttribution(key: 'author', value: 'Ada'));
      expect(
        attribution.hashCode,
        DeltaAttribution(key: 'author', value: 'Ada').hashCode,
      );
      expect(attributed.isUnattributed, isFalse);
      expect(attributed.toJson(), {
        'delta': {
          'ops': [
            {'insert': 'x'},
          ],
        },
        'insertions': [
          {'key': 'author', 'value': 'Ada'},
        ],
        'deletions': [
          {'key': 'author', 'value': 'Bob'},
        ],
        'formatting': [
          {'key': 'format', 'value': true},
        ],
      });
      expect(
        attributed,
        AttributedDelta(
          delta: Delta([DeltaInsertText(text: 'x')]),
          insertions: [attribution],
          deletions: [otherAttribution],
          formatting: [DeltaAttribution(key: 'format', value: true)],
        ),
      );
      expect(attributed.hashCode, attributed.hashCode);
      expect(attributed.toString(), attributed.toJson().toString());
    });
  });
}
