import 'package:block_editor/block_editor.dart';
import 'package:test/test.dart';

void main() {
  group('BlockTypes', () {
    test('all constants are non-empty strings', () {
      final all = [
        BlockTypes.paragraph,
        BlockTypes.heading1,
        BlockTypes.heading2,
        BlockTypes.heading3,
        BlockTypes.bulletList,
        BlockTypes.numberedList,
        BlockTypes.todo,
        BlockTypes.quote,
        BlockTypes.callout,
        BlockTypes.code,
        BlockTypes.divider,
        BlockTypes.image,
        BlockTypes.video,
        BlockTypes.youtube,
        BlockTypes.file,
        BlockTypes.link,
      ];
      for (final type in all) {
        expect(type, isNotEmpty);
      }
    });

    test('all constants are unique', () {
      final all = [
        BlockTypes.paragraph,
        BlockTypes.heading1,
        BlockTypes.heading2,
        BlockTypes.heading3,
        BlockTypes.bulletList,
        BlockTypes.numberedList,
        BlockTypes.todo,
        BlockTypes.quote,
        BlockTypes.callout,
        BlockTypes.code,
        BlockTypes.divider,
        BlockTypes.image,
        BlockTypes.video,
        BlockTypes.youtube,
        BlockTypes.file,
        BlockTypes.link,
      ];
      expect(all.toSet().length, equals(all.length));
    });

    test('all constants are lowercase with no spaces', () {
      final all = [
        BlockTypes.paragraph,
        BlockTypes.heading1,
        BlockTypes.heading2,
        BlockTypes.heading3,
        BlockTypes.bulletList,
        BlockTypes.numberedList,
        BlockTypes.todo,
        BlockTypes.quote,
        BlockTypes.callout,
        BlockTypes.code,
        BlockTypes.divider,
        BlockTypes.image,
        BlockTypes.video,
        BlockTypes.youtube,
        BlockTypes.file,
        BlockTypes.link,
      ];
      for (final type in all) {
        expect(type.contains(' '), isFalse);
        expect(type, isNot(contains(RegExp(r'[A-Z]').pattern)));
      }
    });
  });
}
