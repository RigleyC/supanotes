import 'package:drift/drift.dart' hide isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/database/note_lifecycle_policy.dart';

void main() {
  late AppDatabase db;
  const userId = 'user-1';
  const noteId = 'note-1';
  final now = DateTime(2026, 7, 6);

  setUp(() async {
    db = AppDatabase.test();
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: noteId,
            userId: userId,
            content: '',
            createdAt: now,
            updatedAt: now,
            hasRemoteCopy: const Value(true),
            lifecycleState: const Value(materializedLifecycleState),
          ),
        );
  });

  tearDown(() => db.close());

  test('setCollapseImages marks the preference row dirty and materializes', () async {
    await db.userNotePreferencesDao.setCollapseImages(userId, noteId, true);

    final pref = await db.userNotePreferencesDao.getPreference(userId, noteId);
    expect(pref, isNotNull);
    expect(pref!.collapseImages, isTrue);
    expect(pref.isDirty, isTrue);

    final note = await db.notesDao.getNoteById(noteId);
    expect(note!.lifecycleState, materializedLifecycleState);
  });

  test('remote data is clean and applies to a clean row', () async {
    final applied = await db.userNotePreferencesDao.applyRemotePreference(
      userId: userId,
      noteId: noteId,
      favorite: false,
      archived: false,
      hideCompleted: false,
      collapseImages: true,
      remoteUpdatedAt: now,
    );

    expect(applied, isTrue);
    final pref = await db.userNotePreferencesDao.getPreference(userId, noteId);
    expect(pref!.collapseImages, isTrue);
    expect(pref.isDirty, isFalse);
    expect(pref.updatedAt, now);
  });

  test('remote data cannot replace a dirty local row', () async {
    await db.userNotePreferencesDao.setCollapseImages(userId, noteId, true);

    final applied = await db.userNotePreferencesDao.applyRemotePreference(
      userId: userId,
      noteId: noteId,
      favorite: false,
      archived: false,
      hideCompleted: false,
      collapseImages: false,
      remoteUpdatedAt: now,
    );

    expect(applied, isFalse);
    final pref = await db.userNotePreferencesDao.getPreference(userId, noteId);
    expect(pref!.collapseImages, isTrue);
    expect(pref.isDirty, isTrue);
  });

  test('clearDirtyFlag only clears when timestamps match', () async {
    await db.userNotePreferencesDao.setCollapseImages(userId, noteId, true);
    final pref = await db.userNotePreferencesDao.getPreference(userId, noteId);

    await db.userNotePreferencesDao.clearDirtyFlag(
      userId,
      noteId,
      now.add(const Duration(hours: 1)),
    );
    expect(
      (await db.userNotePreferencesDao.getPreference(userId, noteId))!.isDirty,
      isTrue,
    );

    await db.userNotePreferencesDao.clearDirtyFlag(userId, noteId, pref!.updatedAt);
    expect(
      (await db.userNotePreferencesDao.getPreference(userId, noteId))!.isDirty,
      isFalse,
    );
  });

  test('setPreferences writes all four fields as one dirty row', () async {
    await db.userNotePreferencesDao.setPreferences(
      userId: userId,
      noteId: noteId,
      favorite: true,
      archived: false,
      hideCompleted: true,
      collapseImages: true,
    );

    final pref = await db.userNotePreferencesDao.getPreference(userId, noteId);
    expect(pref!.favorite, isTrue);
    expect(pref.archived, isFalse);
    expect(pref.hideCompleted, isTrue);
    expect(pref.collapseImages, isTrue);
    expect(pref.isDirty, isTrue);
  });

  group('v29 to v30 migration', () {
    test('preserves the old local collapse value under its owner preference', () async {
      final db = AppDatabase.test();

      // Recreate the v29 shapes the migration reads, writes and drops, then
      // run the real migration step `_onUpgrade` executes.
      await db.customStatement(
        'ALTER TABLE notes ADD COLUMN collapse_images INTEGER NOT NULL DEFAULT 0',
      );
      await db.customStatement(
        'ALTER TABLE user_note_preferences DROP COLUMN collapse_images',
      );
      await db.customStatement(
        "INSERT INTO notes "
        "(id, user_id, content, created_at, updated_at, has_remote_copy, "
        "lifecycle_state, collapse_images) "
        "VALUES ('migrated-note', 'owner-1', '', strftime('%s', 'now'), "
        "strftime('%s', 'now'), 1, '$materializedLifecycleState', 1)",
      );
      await migratePerUserCollapse(db, Migrator(db), 29);

      final pref = await db.userNotePreferencesDao
          .getPreference('owner-1', 'migrated-note');
      expect(pref, isNotNull);
      expect(pref!.collapseImages, isTrue);
      expect(pref.isDirty, isTrue);

      final note = await db.notesDao.getNoteById('migrated-note');
      expect(note!.lifecycleState, materializedLifecycleState);

      final columns = await db.customSelect('PRAGMA table_info(notes)').get();
      expect(
        columns.any((column) => column.data['name'] == 'collapse_images'),
        isFalse,
      );

      await db.close();
    });
  });
}