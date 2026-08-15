import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';
import 'package:supanotes/core/database/daos/notes_dao.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/database/note_lifecycle_policy.dart';
import 'package:supanotes/features/notes/catalog/model/note_strings.dart';

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

    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: 'note-title-1',
            userId: 'user-1',
            content: 'My Trip\n\nsome details',
            createdAt: now,
            updatedAt: now,
            lifecycleState: const Value(materializedLifecycleState),
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

    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: 'note-title-2',
            userId: 'user-1',
            content: '',
            createdAt: now,
            updatedAt: now,
            hasRemoteCopy: const Value(true),
            lifecycleState: const Value(materializedLifecycleState),
          ),
        );

    final notes = await db.notesDao.watchAllActiveNotes('user-1').first;
    expect(notes, hasLength(1));
    expect(notes.first.title, NoteStrings.fallbackTitle);

    await db.close();
  });

  test(
    'watchAllActiveNotes hides untouched drafts but keeps attachments',
    () async {
      final db = AppDatabase.test();
      final now = DateTime(2026, 7, 6);

      await db
          .into(db.notes)
          .insert(
            NotesCompanion.insert(
              id: 'empty-draft',
              userId: 'user-1',
              content: '',
              createdAt: now,
              updatedAt: now,
              hasRemoteCopy: const Value(false),
            ),
          );
      await db
          .into(db.notes)
          .insert(
            NotesCompanion.insert(
              id: 'outbox-draft',
              userId: 'user-1',
              content: '',
              createdAt: now,
              updatedAt: now,
              hasRemoteCopy: const Value(false),
            ),
          );
      await db
          .into(db.notes)
          .insert(
            NotesCompanion.insert(
              id: 'attachment-draft',
              userId: 'user-1',
              content: '',
              createdAt: now,
              updatedAt: now,
              hasRemoteCopy: const Value(false),
            ),
          );
      await db.attachmentsDao.upsert(
        AttachmentsCompanion.insert(
          id: 'attachment-1',
          noteId: 'attachment-draft',
          fileName: 'image.png',
          mimeType: 'image/png',
          fileSize: 1,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await db.noteOperationsDao.insertPendingOperation(
        PendingNoteOperationsCompanion.insert(
          operationId: 'outbox-operation-1',
          noteId: 'outbox-draft',
          baseRevision: 0,
          ordinal: 0,
          kind: 'text_delta',
          payloadJson: '{}',
          createdAt: now,
        ),
      );

      final notes = await db.notesDao.watchAllActiveNotes('user-1').first;
      expect(notes.map((note) => note.note.id), [
        'outbox-draft',
        'attachment-draft',
      ]);

      await db.close();
    },
  );

  test('keeps local drafts with meaningful note metadata', () async {
    final db = AppDatabase.test();
    final now = DateTime(2026, 7, 6);

    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: 'icon-draft',
            userId: 'user-1',
            content: '',
            createdAt: now,
            updatedAt: now,
            noteIconJson: const Value('{"kind":"emoji","value":"🔥"}'),
            lifecycleState: const Value(materializedLifecycleState),
          ),
        );
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: 'favorite-draft',
            userId: 'user-1',
            content: '',
            createdAt: now,
            updatedAt: now,
            lifecycleState: const Value(materializedLifecycleState),
          ),
        );
    await db
        .into(db.userNotePreferences)
        .insert(
          UserNotePreferencesCompanion.insert(
            userId: 'user-1',
            noteId: 'favorite-draft',
            favorite: const Value(true),
          ),
        );

    final notes = await db.notesDao.watchAllActiveNotes('user-1').first;
    expect(
      notes.map((note) => note.note.id),
      unorderedEquals(['icon-draft', 'favorite-draft']),
    );

    await db.close();
  });

  test('projects collapse_images from the preference join', () async {
    final db = AppDatabase.test();
    final now = DateTime(2026, 7, 6);

    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: 'collapse-note',
            userId: 'user-1',
            content: 'collapsed body',
            createdAt: now,
            updatedAt: now,
            lifecycleState: const Value(materializedLifecycleState),
          ),
        );

    await db.userNotePreferencesDao.setCollapseImages(
      'user-1',
      'collapse-note',
      true,
    );

    final qr = await db.notesDao.getNoteWithPrefsById(
      'collapse-note',
      'user-1',
    );
    expect(qr!.collapseImages, isTrue);

    await db.close();
  });

  test('does not reset a materialized note on an empty upsert', () async {
    final db = AppDatabase.test();
    final now = DateTime(2026, 7, 6);
    addTearDown(db.close);

    await db.notesDao.createNote(
      NotesCompanion.insert(
        id: 'materialized-note',
        userId: 'user-1',
        content: 'Saved content',
        createdAt: now,
        updatedAt: now,
      ),
    );

    await db.notesDao.upsertNote(
      NotesCompanion.insert(
        id: 'materialized-note',
        userId: 'user-1',
        content: '',
        createdAt: now,
        updatedAt: now.add(const Duration(seconds: 1)),
      ),
    );

    expect(
      (await db.notesDao.getNoteById('materialized-note'))!.lifecycleState,
      materializedLifecycleState,
    );
  });
}
