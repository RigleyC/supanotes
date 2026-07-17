import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/core/database/daos/notes_dao.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/features/notes/domain/note_strings.dart';

void main() {
  group('deriveNoteTitle', () {
    test('returns first line stripped of markdown heading', () {
      expect(deriveNoteTitle('# My Trip\n\nBody'), 'My Trip');
    });

    test('returns first line stripped of task checkbox', () {
      expect(deriveNoteTitle('- [ ] Comprar leite\n\nBody'), 'Comprar leite');
      expect(deriveNoteTitle('- [x] Comprar leite\n\nBody'), 'Comprar leite');
    });

    test('returns first line stripped of bullet marker', () {
      expect(deriveNoteTitle('- Item\n\nBody'), 'Item');
      expect(deriveNoteTitle('* Item\n\nBody'), 'Item');
    });

    test('returns first line stripped of ordered list marker', () {
      expect(deriveNoteTitle('1. Item\n\nBody'), 'Item');
    });

    test('skips leading empty lines', () {
      expect(deriveNoteTitle('\n\nMy Trip\nBody'), 'My Trip');
    });

    test('returns fallback when content is empty', () {
      expect(deriveNoteTitle(''), NoteStrings.fallbackTitle);
    });
  });
  test('watchAllActiveNotes derives title from first text node', () async {
    final db = AppDatabase.test();
    final now = DateTime(2026, 7, 6);

    await db.into(db.notes).insert(
          NotesCompanion.insert(
            id: 'note-title-1',
            userId: 'user-1',
            content: 'My Trip\n\nsome details',
            createdAt: now,
            updatedAt: now,
          ),
        );

    final notes = await db.notesDao.watchAllActiveNotes('user-1').first;
    expect(notes, hasLength(1));
    expect(notes.first.title, 'My Trip');

    await db.close();
  });

  test('watchAllActiveNotes falls back when note has no text nodes', () async {
    final db = AppDatabase.test();
    final now = DateTime(2026, 7, 6);

    await db.into(db.notes).insert(
          NotesCompanion.insert(
            id: 'note-title-2',
            userId: 'user-1',
            content: '',
            createdAt: now,
            updatedAt: now,
          ),
        );

    final notes = await db.notesDao.watchAllActiveNotes('user-1').first;
    expect(notes, hasLength(1));
    expect(notes.first.title, NoteStrings.fallbackTitle);

    await db.close();
  });
}
