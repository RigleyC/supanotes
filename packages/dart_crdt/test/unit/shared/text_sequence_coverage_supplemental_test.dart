import 'package:dart_crdt/src/content/content.dart';
import 'package:dart_crdt/src/delta/delta_operation.dart';
import 'package:dart_crdt/src/doc/doc.dart';
import 'package:test/test.dart';

void main() {
  group('shared text and sequence supplemental coverage', () {
    test('covers sequence placeholder, marker, empty insert, and zero delete',
        () {
      final placeholder = const SequencePlaceholder('pending');
      final marker = const SequenceSearchMarker(index: 0, value: 'a');
      final array = SharedType(kind: SharedTypeKind.array);

      array
        ..insertAll(0, const <Object?>[])
        ..push('a')
        ..delete(1, 0);

      expect(placeholder, const SequencePlaceholder('pending'));
      expect(
        placeholder.hashCode,
        const SequencePlaceholder('pending').hashCode,
      );
      expect(placeholder.toString(), 'SequencePlaceholder(pending)');
      expect(marker, const SequenceSearchMarker(index: 0, value: 'a'));
      expect(
        marker.hashCode,
        const SequenceSearchMarker(index: 0, value: 'a').hashCode,
      );
      expect(
        marker == const SequenceSearchMarker(index: 1, value: 'a'),
        isFalse,
      );
      expect(array.searchMarkers, [marker]);
      expect(() => array.delete(0, -1), throwsRangeError);
    });

    test('covers text guards, no-op formatting, and unsupported delta ops', () {
      final text = SharedType(kind: SharedTypeKind.text)
        ..insertText(0, '')
        ..insertText(0, 'abc');
      final deleteAttrs = DeltaAttributes.fromJson({'bold': null});

      text
        ..deleteText(1, 0)
        ..format(1, 0, DeltaAttributes.fromJson({'bold': true}))
        ..format(0, 1, DeltaAttributes.empty)
        ..format(0, 1, DeltaAttributes.fromJson({'bold': true}))
        ..format(0, 1, DeltaAttributes.fromJson({'bold': true}));

      expect(
        () => text.insertText(0, 'x', attributes: deleteAttrs),
        throwsArgumentError,
      );
      expect(
        () => text.insertEmbed(0, 'x', attributes: deleteAttrs),
        throwsArgumentError,
      );
      expect(
        () => text.applyDelta(
          Delta([
            DeltaModifyChild(operations: [DeltaRetain(length: 1)]),
          ]),
        ),
        throwsUnsupportedError,
      );
      expect(
        () => text.applyDelta(
          Delta([DeltaSetAttribute(key: 'title', value: 'A')]),
        ),
        returnsNormally,
      );
      expect(text.toDelta().toJson(), {
        'ops': [
          {
            'insert': 'a',
            'attributes': {'bold': true},
          },
          {'insert': 'bc'},
        ],
      });
    });

    test(
        'covers applyDelta list inserts, deletes, and shared type string rendering',
        () {
      final text = SharedType(kind: SharedTypeKind.text)..insertText(0, 'xy');
      final map = SharedType(kind: SharedTypeKind.map, name: 'card')
        ..setAttr('title', 'T');
      final xml = SharedType(kind: SharedTypeKind.xmlElement, name: 'p')
        ..appendXmlText('x');

      text.applyDelta(
        Delta([
          DeltaRetain(length: 1),
          DeltaDelete(1),
          DeltaInsertListContent.fromObjects([
            {'embed': true},
          ]),
        ]),
      );

      expect(text.toPlainText(), 'x\uFFFC');
      expect(text.toDelta().toJson(), {
        'ops': [
          {'insert': 'x'},
          {
            'insert': [
              {'embed': true},
            ],
          },
        ],
      });
      expect(map.toString(), 'map:card');
      expect(xml.toString(), '<p>x</p>');
    });
  });
}
