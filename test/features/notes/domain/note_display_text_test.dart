import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/notes/domain/note_display_text.dart';

void main() {
  group('deriveNoteExcerpt', () {
    test('extracts text after title line', () {
      expect(deriveNoteExcerpt("Trip\nBuy tickets\nBook hotel"), equals("Buy tickets Book hotel"));
    });

    test('returns null if no content after title', () {
      expect(deriveNoteExcerpt("Trip"), isNull);
    });
  });
}
