import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/features/notes/data/note_catalog_sync.dart';
import 'package:supanotes/features/notes/data/note_sync_client.dart';
import 'package:supanotes/features/notes/domain/note_session_activity_tracker.dart';

class _MockNoteSyncClient extends Mock implements NoteSyncClient {}

void main() {
  test(
    'removes a remote note that disappeared from the server catalog',
    () async {
      final database = AppDatabase.test();
      final client = _MockNoteSyncClient();
      final sync = NoteCatalogSync(
        syncClient: client,
        database: database,
        activityTracker: NoteSessionActivityTracker(),
      );
      addTearDown(database.close);

      await database
          .into(database.notes)
          .insert(
            NotesCompanion.insert(
              id: 'remote-note',
              userId: 'user-a',
              content: 'Deleted elsewhere',
              createdAt: DateTime.utc(2026, 7, 31),
              updatedAt: DateTime.utc(2026, 7, 31),
              isDirty: const Value(false),
              hasRemoteCopy: const Value(true),
            ),
          );
      when(() => client.listNotes()).thenAnswer((_) async => const []);

      await sync.pullRemoteNotes('user-a');

      expect(await database.notesDao.getNoteById('remote-note'), isNull);
    },
  );

  test('pushes a local tombstone before removing the note locally', () async {
    final database = AppDatabase.test();
    final client = _MockNoteSyncClient();
    final sync = NoteCatalogSync(
      syncClient: client,
      database: database,
      activityTracker: NoteSessionActivityTracker(),
    );
    addTearDown(database.close);

    await database
        .into(database.notes)
        .insert(
          NotesCompanion.insert(
            id: 'deleted-note',
            userId: 'user-a',
            content: 'Deleted here',
            createdAt: DateTime.utc(2026, 7, 31),
            updatedAt: DateTime.utc(2026, 7, 31),
            deletedAt: Value(DateTime.utc(2026, 7, 31, 12)),
            isDirty: const Value(true),
            hasRemoteCopy: const Value(true),
          ),
        );
    when(() => client.deleteNote('deleted-note')).thenAnswer((_) async {});

    await sync.pushDeletedNotes();

    verify(() => client.deleteNote('deleted-note')).called(1);
    expect(await database.notesDao.getNoteById('deleted-note'), isNull);
  });

  test(
    'hard-deletes a local-only tombstone without sending a remote delete',
    () async {
      final database = AppDatabase.test();
      final client = _MockNoteSyncClient();
      final sync = NoteCatalogSync(
        syncClient: client,
        database: database,
        activityTracker: NoteSessionActivityTracker(),
      );
      addTearDown(database.close);

      await database
          .into(database.notes)
          .insert(
            NotesCompanion.insert(
              id: 'local-only-deleted-note',
              userId: 'user-a',
              content: 'Never synced',
              createdAt: DateTime.utc(2026, 7, 31),
              updatedAt: DateTime.utc(2026, 7, 31),
              deletedAt: Value(DateTime.utc(2026, 7, 31, 12)),
              isDirty: const Value(true),
              hasRemoteCopy: const Value(false),
            ),
          );

      await sync.pushDeletedNotes();

      verifyNever(() => client.deleteNote('local-only-deleted-note'));
      expect(
        await database.notesDao.getNoteById('local-only-deleted-note'),
        isNull,
      );
    },
  );

  test('keeps a remote tombstone after failure and retries it later', () async {
    final database = AppDatabase.test();
    final client = _MockNoteSyncClient();
    final sync = NoteCatalogSync(
      syncClient: client,
      database: database,
      activityTracker: NoteSessionActivityTracker(),
    );
    addTearDown(database.close);

    await database
        .into(database.notes)
        .insert(
          NotesCompanion.insert(
            id: 'retry-deleted-note',
            userId: 'user-a',
            content: 'Retry me',
            createdAt: DateTime.utc(2026, 7, 31),
            updatedAt: DateTime.utc(2026, 7, 31),
            deletedAt: Value(DateTime.utc(2026, 7, 31, 12)),
            isDirty: const Value(true),
            hasRemoteCopy: const Value(true),
          ),
        );
    var attempts = 0;
    when(() => client.deleteNote('retry-deleted-note')).thenAnswer((_) async {
      attempts++;
      if (attempts == 1) {
        throw StateError('offline');
      }
    });

    await expectLater(sync.pushDeletedNotes(), throwsA(isA<StateError>()));
    expect(
      await database.notesDao.getNoteById('retry-deleted-note'),
      isNotNull,
    );

    await sync.pushDeletedNotes();

    verify(() => client.deleteNote('retry-deleted-note')).called(2);
    expect(await database.notesDao.getNoteById('retry-deleted-note'), isNull);
  });

  test(
    'does not remove a note opened while remote deletion was in flight',
    () async {
      final database = AppDatabase.test();
      final client = _MockNoteSyncClient();
      final activityTracker = NoteSessionActivityTracker();
      final sync = NoteCatalogSync(
        syncClient: client,
        database: database,
        activityTracker: activityTracker,
      );
      addTearDown(database.close);

      await database
          .into(database.notes)
          .insert(
            NotesCompanion.insert(
              id: 'race-deleted-note',
              userId: 'user-a',
              content: 'Keep the active session',
              createdAt: DateTime.utc(2026, 7, 31),
              updatedAt: DateTime.utc(2026, 7, 31),
              deletedAt: Value(DateTime.utc(2026, 7, 31, 12)),
              isDirty: const Value(true),
              hasRemoteCopy: const Value(true),
            ),
          );
      when(() => client.deleteNote('race-deleted-note')).thenAnswer((_) async {
        activityTracker.markActive('race-deleted-note');
      });

      await sync.pushDeletedNotes();

      expect(
        await database.notesDao.getNoteById('race-deleted-note'),
        isNotNull,
      );
    },
  );

  test(
    'keeps a missing remote note while its editor session is active',
    () async {
      final database = AppDatabase.test();
      final client = _MockNoteSyncClient();
      final activityTracker = NoteSessionActivityTracker()
        ..markActive('open-note');
      final sync = NoteCatalogSync(
        syncClient: client,
        database: database,
        activityTracker: activityTracker,
      );
      addTearDown(database.close);

      await database
          .into(database.notes)
          .insert(
            NotesCompanion.insert(
              id: 'open-note',
              userId: 'user-a',
              content: 'Open elsewhere',
              createdAt: DateTime.utc(2026, 7, 31),
              updatedAt: DateTime.utc(2026, 7, 31),
              isDirty: const Value(false),
              hasRemoteCopy: const Value(true),
            ),
          );
      when(() => client.listNotes()).thenAnswer((_) async => const []);

      await sync.pullRemoteNotes('user-a');

      expect(await database.notesDao.getNoteById('open-note'), isNotNull);
    },
  );
}
