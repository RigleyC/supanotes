import 'dart:developer' as dev;
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'daos/attachments_dao.dart';
import 'daos/note_links_dao.dart';
import 'daos/note_operations_dao.dart';
import 'daos/notes_dao.dart';
import 'daos/task_completions_dao.dart';
import 'daos/tasks_dao.dart';
import 'daos/user_note_preferences_dao.dart';
import 'tables/attachments.dart';
import 'tables/local_note_documents.dart';
import 'tables/local_yjs_states.dart';
import 'tables/note_links.dart';
import 'tables/note_sync_errors.dart';
import 'tables/sync_sessions.dart';
import 'tables/notes.dart';
import 'tables/pending_note_operations.dart';
import 'tables/task_completions.dart';
import 'tables/tasks.dart';
import 'tables/user_note_preferences.dart';

import '../../features/tasks/domain/task_recurrence.dart'; // Needed for EnumNameConverter in tasks.dart

part 'database.g.dart';

@DriftDatabase(
  tables: [
    Notes,
    Tasks,
    LocalTaskCompletions,
    NoteLinks,
    Attachments,
    UserNotePreferences,
    LocalYjsStates,
    LocalNoteDocuments,
    PendingNoteOperations,
    NoteSyncErrors,
    SyncSessions,
  ],
  daos: [
    NotesDao,
    TasksDao,
    TaskCompletionsDao,
    NoteLinksDao,
    AttachmentsDao,
    UserNotePreferencesDao,
    NoteOperationsDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.test({QueryExecutor? executor})
    : super(executor ?? NativeDatabase.memory());

  Future<void> clearAllData() async {
    await transaction(() async {
      for (final entity in allSchemaEntities) {
        if (entity is TableInfo) {
          await delete(entity).go();
        }
      }
    });
  }

  @override
  int get schemaVersion => 22;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(localTaskCompletions);
        await m.addColumn(tasks, tasks.completedAt);
      }
      if (from < 3) {
        await m.addColumn(notes, notes.hasRemoteCopy);
      }
      if (from < 4) {
        await m.createTable(noteLinks);
      } else if (from == 4) {
        try {
          await m.addColumn(noteLinks, noteLinks.createdAt);
        } catch (_) {}
        try {
          await m.addColumn(noteLinks, noteLinks.updatedAt);
        } catch (_) {}
      }
      if (from < 6) {
        await customStatement(
          'ALTER TABLE notes ADD COLUMN hide_completed INTEGER NOT NULL DEFAULT 0',
        );
      }
      if (from < 7) {
        await m.addColumn(notes, notes.permission);
        await m.addColumn(notes, notes.sharedByEmail);
        await m.addColumn(notes, notes.sharedByName);
      }
      if (from < 8) {
        try {
          await customStatement('ALTER TABLE notes DROP COLUMN title');
        } catch (e) {
          dev.log(
            'Failed to drop note title column during migration: $e',
            name: 'DatabaseMigration',
          );
        }
      }
      if (from < 9) {
        await m.createTable(attachments);
      }
      if (from < 10) {
        await m.addColumn(notes, notes.collapseImages);
      }
      if (from < 11) {
        await m.createTable(userNotePreferences);
        await customStatement('ALTER TABLE notes DROP COLUMN hide_completed');
      }
      if (from < 12) {
        await m.addColumn(userNotePreferences, userNotePreferences.favorite);
        await m.addColumn(userNotePreferences, userNotePreferences.archived);
        await customStatement(
          'INSERT OR IGNORE INTO user_note_preferences (user_id, note_id, favorite, archived, created_at, updated_at, is_dirty) '
          'SELECT n.user_id, n.id, n.favorite, n.archived, n.created_at, n.updated_at, 0 FROM notes n',
        );
        await customStatement('ALTER TABLE notes DROP COLUMN favorite');
        await customStatement('ALTER TABLE notes DROP COLUMN archived');
      }
      if (from < 13) {
        // note_nodes table was historically created here; now dropped in favor of YDoc
      }
      if (from < 14) {
        // note_nodes position migration; now unnecessary

        await customStatement('PRAGMA foreign_keys=ON;');
      }
      if (from < 15) {
        await customStatement('DELETE FROM notes WHERE is_inbox = 1;');
        await customStatement('ALTER TABLE notes DROP COLUMN is_inbox;');
      }
      if (from < 16) {
        await m.createTable(localYjsStates);
      }
      if (from < 17) {
        await m.addColumn(tasks, tasks.hasTime);
      }
      if (from < 18) {
        await m.addColumn(tasks, tasks.reminder);
      }
      if (from < 19) {
        await m.addColumn(localYjsStates, localYjsStates.syncedStateVector);
      }
      if (from < 20) {
        await customStatement(
          'ALTER TABLE local_task_completions ADD COLUMN scheduled_at INTEGER NOT NULL DEFAULT 0',
        );
        await customStatement(
          'UPDATE local_task_completions SET scheduled_at = completed_at',
        );
        await customStatement(
          'CREATE UNIQUE INDEX IF NOT EXISTS local_task_completions_task_scheduled_idx ON local_task_completions(task_id, scheduled_at)',
        );
      }
      if (from < 21) {
        await m.createTable(localNoteDocuments);
        await m.createTable(pendingNoteOperations);
        await m.createTable(noteSyncErrors);
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_pending_ops_note_ordinal ON pending_note_operations(note_id, ordinal)',
        );
      }
      if (from == 21) {
        await m.addColumn(pendingNoteOperations, pendingNoteOperations.status);
      }
      if (from < 22) {
        await m.createTable(syncSessions);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'supanotes.sqlite'));

    final cachebase = (await getTemporaryDirectory()).path;
    sqlite3.tempDirectory = cachebase;

    return NativeDatabase.createInBackground(file);
  });
}

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  // Wire the cross-DAO dependencies that Drift cannot infer from the
  // schema alone: [TasksDao.completeTask] appends a row to
  // [LocalTaskCompletions], so it needs a reference to the
  // [TaskCompletionsDao] instance. Drift exposes those via getters
  // generated on [AppDatabase], so we can grab them after construction.
  db.tasksDao.completionsDao = db.taskCompletionsDao;
  ref.onDispose(db.close);
  return db;
});
