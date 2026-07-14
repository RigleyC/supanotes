import 'package:dart_crdt/src/content/content.dart';
import 'package:dart_crdt/src/doc/doc.dart';
import 'package:test/test.dart';

void main() {
  group('clearing a shared type to empty', () {
    test('standalone text survives a full single-transaction delete', () {
      final text = SharedType(kind: SharedTypeKind.text)
        ..insertText(0, 'hello world');

      expect(() => text.deleteText(0, 11), returnsNormally);
      expect(text.toPlainText(), isEmpty);
      expect(text.searchMarkers, isEmpty);
    });

    test('root-attached text survives a full single-transaction delete', () {
      final doc = Doc();
      final text = doc.getText('body')..insertText(0, 'hello world');

      expect(() => text.deleteText(0, 11), returnsNormally);
      expect(text.toPlainText(), isEmpty);
    });

    test('deleting the last remaining character does not throw', () {
      final text = SharedType(kind: SharedTypeKind.text)..insertText(0, 'x');

      expect(() => text.deleteText(0, 1), returnsNormally);
      expect(text.toPlainText(), isEmpty);
    });

    test('text remains usable after being emptied', () {
      final text = SharedType(kind: SharedTypeKind.text)
        ..insertText(0, 'abc')
        ..deleteText(0, 3);

      expect(() => text.insertText(0, 'fresh'), returnsNormally);
      expect(text.toPlainText(), 'fresh');
    });

    test('array survives a full single-transaction delete', () {
      final array = SharedType(kind: SharedTypeKind.array)
        ..insertAll(0, const <Object?>['a', 'b', 'c']);

      expect(() => array.delete(0, 3), returnsNormally);
      expect(array.toArray(), isEmpty);
      expect(array.searchMarkers, isEmpty);
      expect(() => array.push('d'), returnsNormally);
      expect(array.toArray(), ['d']);
    });
  });
}
