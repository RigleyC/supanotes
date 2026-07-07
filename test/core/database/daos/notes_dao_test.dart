import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/features/notes/domain/note_strings.dart';

void main() {
  test('watchAllActiveNotes derives title from first text node', () async {
    final db = AppDatabase.test();
    final now = DateTime(2026, 7, 6);

    await db.into(db.notes).insert(
          NotesCompanion.insert(
            id: 'note-title-1',
            userId: 'user-1',
            content: 'irrelevant snapshot',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db.into(db.noteNodes).insert(
          NoteNodesCompanion.insert(
            id: 'node-1',
            noteId: 'note-title-1',
            position: 0.0,
            type: 'paragraph',
            data: '{"text":"My Trip"}',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db.into(db.noteNodes).insert(
          NoteNodesCompanion.insert(
            id: 'node-2',
            noteId: 'note-title-1',
            position: 1.0,
            type: 'paragraph',
            data: '{"text":"Buy tickets"}',
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
