import 'package:dart_crdt/src/content/content.dart';
import 'package:dart_crdt/src/doc/doc.dart';
import 'package:test/test.dart';

void main() {
  group('SharedType sequence APIs', () {
    test('inserts, pushes, unshifts, deletes, and reads by index', () {
      final sequence = SharedType(kind: SharedTypeKind.array, name: 'items')
        ..push('b')
        ..unshift('a')
        ..insert(2, 'd')
        ..insertAll(2, ['c']);

      expect(sequence.length, 4);
      expect(sequence.get(0), 'a');
      expect(sequence.toArray(), ['a', 'b', 'c', 'd']);
      expect(sequence.slice(1, 3), ['b', 'c']);
      expect(() => sequence.toArray().add('x'), throwsUnsupportedError);
      expect(sequence.searchMarkers, [
        const SequenceSearchMarker(index: 0, value: 'a'),
      ]);

      sequence.delete(1, 2);

      expect(sequence.toArray(), ['a', 'd']);
      expect(sequence.searchMarkers, [
        const SequenceSearchMarker(index: 1, value: 'd'),
      ]);
    });

    test('validates insert, delete, get, and slice boundaries', () {
      final sequence = SharedType(kind: SharedTypeKind.array)..push('a');

      expect(() => sequence.insert(-1, 'x'), throwsRangeError);
      expect(() => sequence.insert(2, 'x'), throwsRangeError);
      expect(() => sequence.get(1), throwsRangeError);
      expect(() => sequence.delete(1), throwsRangeError);
      expect(() => sequence.delete(0, 2), throwsRangeError);
      expect(() => sequence.slice(1, 0), throwsRangeError);

      sequence
        ..insertAll(1, const <Object?>[])
        ..delete(1, 0);

      expect(sequence.toArray(), ['a']);
    });

    test('integrates nested shared types and rejects reused children', () {
      final doc = Doc();
      final parent = doc.get('items', SharedTypeKind.array);
      final child = SharedType(kind: SharedTypeKind.map, name: 'child');
      final text = SharedType(kind: SharedTypeKind.text, name: 'body');

      parent
        ..push('prefix')
        ..push(child)
        ..insert(1, text);

      expect(child.parent, same(parent));
      expect(child.parentKey, 2);
      expect(child.doc, same(doc));
      expect(text.parentKey, 1);
      expect(parent.children[1], same(text));
      expect(parent.children[2], same(child));
      expect(
        () => SharedType(kind: SharedTypeKind.array).push(child),
        throwsA(isA<StateError>()),
      );

      parent.delete(1);

      expect(child.parentKey, 1);
      expect(parent.children[1], same(child));
    });

    test('keeps late-sync placeholder values in sequence order', () {
      const placeholder = SequencePlaceholder('missing remote range');
      final sequence = SharedType(kind: SharedTypeKind.array)
        ..push('known')
        ..push(placeholder)
        ..push('after');

      expect(sequence.toArray(), ['known', placeholder, 'after']);
      expect(sequence.slice(1), [placeholder, 'after']);
      expect(
        placeholder.toString(),
        'SequencePlaceholder(missing remote range)',
      );
    });

    test('supports iteration, map, forEach, and event targets', () {
      final doc = Doc();
      final sequence = doc.get('items', SharedTypeKind.array);
      final iterated = <Object?>[];
      final observed = <String>[];

      sequence.observe((event) {
        observed.add('${event.target.name}:${event.keys.join(',')}');
      });

      doc.transact((_) {
        sequence
          ..push('a')
          ..push('b');
      });

      for (final value in sequence) {
        iterated.add(value);
      }

      expect(iterated, ['a', 'b']);
      expect(sequence.map((value) => '$value!').toList(), ['a!', 'b!']);
      void recordForEach(Object? value) {
        observed.add('forEach:$value');
      }

      sequence.forEach(recordForEach);
      expect(observed, ['items:0,1', 'forEach:a', 'forEach:b']);
    });
  });
}
