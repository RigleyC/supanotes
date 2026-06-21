import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/notes/domain/note_display_text.dart';
import 'package:supanotes/features/notes/domain/note_strings.dart';

void main() {
  group('deriveNoteTitle', () {
    test('extracts title from H1 markdown', () {
      expect(deriveNoteTitle("# Trip\nBuy tickets"), equals("Trip"));
    });

    test('extracts title ignoring leading empty lines', () {
      expect(deriveNoteTitle("\n\nTrip\nBuy tickets"), equals("Trip"));
    });

    test('strips list bullets and checkboxes', () {
      expect(deriveNoteTitle("- item\nbody"), equals("item"));
      expect(deriveNoteTitle("- [ ] task\nbody"), equals("task"));
      expect(deriveNoteTitle("1. item\nbody"), equals("item"));
    });

    test('returns fallback for empty content', () {
      expect(deriveNoteTitle(""), equals(NoteStrings.fallbackTitle));
    });
  });

  group('deriveNoteExcerpt', () {
    test('extracts text after title line', () {
      expect(deriveNoteExcerpt("Trip\nBuy tickets\nBook hotel"), equals("Buy tickets Book hotel"));
    });

    test('returns null if no content after title', () {
      expect(deriveNoteExcerpt("Trip"), isNull);
    });
  });


}
