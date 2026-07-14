import 'package:dart_crdt/src/binary/any_value.dart';
import 'package:dart_crdt/src/delta/delta_operation.dart';
import 'package:test/test.dart';

void main() {
  group('DeltaAttributes', () {
    test('normalizes equality and stable JSON order', () {
      final left = DeltaAttributes([
        DeltaAttributeSet(key: 'italic', value: true),
        DeltaAttributeSet(key: 'bold', value: true),
      ]);
      final right = DeltaAttributes([
        DeltaAttributeSet(key: 'bold', value: true),
        DeltaAttributeSet(key: 'italic', value: true),
      ]);

      expect(left, right);
      expect(left.toJson(), {'bold': true, 'italic': true});
      expect(left.toString(), '{bold: true, italic: true}');
      expect(left['bold'], DeltaAttributeSet(key: 'bold', value: true));
    });

    test('represents null values as remove semantics', () {
      final attrs = DeltaAttributes.fromJson({
        'bold': null,
        'color': '#fff',
      });

      expect(attrs.hasDeletes, isTrue);
      expect(attrs.toJson(), {'bold': null, 'color': '#fff'});
      expect(attrs['bold'], DeltaAttributeDelete('bold'));
      expect(attrs['color'], DeltaAttributeSet(key: 'color', value: '#fff'));
    });

    test('supports nested modify-attribute formatting changes', () {
      final attrs = DeltaAttributes([
        DeltaAttributeModify(
          key: 'comment',
          operations: [DeltaInsertText(text: 'note')],
        ),
      ]);

      expect(attrs.toJson(), {
        'comment': {
          'ops': [
            {'insert': 'note'},
          ],
        },
      });
    });
  });

  group('Delta content operations', () {
    test('creates insert, retain, delete, and modify operations', () {
      final text = DeltaInsertText(
        text: 'hi',
        attributes: DeltaAttributes.fromJson({'bold': true}),
      );
      final list = DeltaInsertListContent.fromObjects([
        'a',
        1,
        null,
      ]);
      final retain = DeltaRetain(
        length: 3,
        attributes: DeltaAttributes.fromJson({'bold': null}),
      );
      final delete = DeltaDelete(2);
      final modify = DeltaModifyChild(
        operations: [DeltaRetain(length: 1)],
        attributes: DeltaAttributes.fromJson({'mark': true}),
      );

      expect(text.length, 2);
      expect(text.toJson(), {
        'insert': 'hi',
        'attributes': {'bold': true},
      });
      expect(list.length, 3);
      expect(list.values, [
        const JsonString('a'),
        JsonNumber(1),
        const JsonNull(),
      ]);
      expect(list.toJson(), {
        'insert': ['a', 1, null],
      });
      expect(retain.toJson(), {
        'retain': 3,
        'attributes': {'bold': null},
      });
      expect(delete.toJson(), {'delete': 2});
      expect(modify.toJson(), {
        'modify': [
          {'retain': 1},
        ],
        'attributes': {'mark': true},
      });
    });

    test('implements equality and debug rendering', () {
      final first = DeltaInsertText(text: 'same');
      final second = DeltaInsertText(text: 'same');

      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect(first.toDebugString(), '{insert: same}');
      expect(first.toString(), first.toDebugString());
    });
  });

  group('Delta attribute operations', () {
    test('creates set, delete, and modify attribute operations', () {
      final set = DeltaSetAttribute(key: 'title', value: 'Hello');
      final delete = DeltaDeleteAttribute('title');
      final modify = DeltaModifyAttribute(
        key: 'child',
        operations: [DeltaInsertText(text: 'nested')],
      );

      expect(set.isAttributeOperation, isTrue);
      expect(set.length, 0);
      expect(set.toJson(), {'setAttribute': 'title', 'value': 'Hello'});
      expect(delete.toJson(), {'deleteAttribute': 'title'});
      expect(modify.toJson(), {
        'modifyAttribute': 'child',
        'delta': [
          {'insert': 'nested'},
        ],
      });
      expect(set, DeltaSetAttribute(key: 'title', value: 'Hello'));
      expect(delete, DeltaDeleteAttribute('title'));
    });
  });

  group('Delta operation validation', () {
    test('rejects invalid lengths and empty inserts', () {
      expect(() => DeltaRetain(length: 0), throwsRangeError);
      expect(() => DeltaDelete(0), throwsRangeError);
      expect(() => DeltaInsertText(text: ''), throwsArgumentError);
      expect(
        () => DeltaInsertListContent(const <AnyValue>[]),
        throwsArgumentError,
      );
    });

    test('rejects invalid attribute and nested operation combinations', () {
      expect(
        () => DeltaInsertText(
          text: 'x',
          attributes: DeltaAttributes.fromJson({'bold': null}),
        ),
        throwsArgumentError,
      );
      expect(
        () => DeltaAttributes([
          DeltaAttributeSet(key: 'bold', value: true),
          DeltaAttributeDelete('bold'),
        ]),
        throwsArgumentError,
      );
      expect(
        () => DeltaSetAttribute(key: 'x', value: null),
        throwsArgumentError,
      );
      expect(() => DeltaDeleteAttribute(''), throwsArgumentError);
      expect(
        () => DeltaModifyChild(operations: const <DeltaOperation>[]),
        throwsArgumentError,
      );
      expect(
        () => DeltaModifyAttribute(
          key: 'child',
          operations: const <DeltaOperation>[],
        ),
        throwsArgumentError,
      );
    });
  });
}
