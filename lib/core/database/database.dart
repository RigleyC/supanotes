import 'dart:developer' as dev;
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'daos/attachments_dao.dart';
import 'daos/contexts_dao.dart';
import 'daos/note_links_dao.dart';
import 'daos/note_tags_dao.dart';
import 'daos/notes_dao.dart';
import 'daos/tags_dao.dart';
import 'daos/task_completions_dao.dart';
import 'daos/tasks_dao.dart';
import 'daos/user_note_preferences_dao.dart';
import 'tables/attachments.dart';
import 'tables/contexts.dart';
import 'tables/local_yjs_states.dart';
import 'tables/note_links.dart';
import 'tables/note_nodes.dart';
import 'tables/note_tags.dart';
import 'tables/notes.dart';
import 'tables/tags.dart';
import 'tables/task_completions.dart';
import 'tables/tasks.dart';
import 'tables/user_note_preferences.dart';

import '../../features/tasks/domain/task_recurrence.dart'; // Needed for EnumNameConverter in tasks.dart

part 'database.g.dart';

@DriftDatabase(
  tables: [
    Notes,
    Tasks,
    Contexts,
    Tags,
    LocalNoteTags,
    LocalTaskCompletions,
    NoteLinks,
    Attachments,
    UserNotePreferences,
    NoteNodes,
    LocalYjsStates,
  ],
  daos: [
    NotesDao,
    ContextsDao,
    TasksDao,
    TagsDao,
    TaskCompletionsDao,
    NoteLinksDao,
    NoteTagsDao,
    AttachmentsDao,
    UserNotePreferencesDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.test({QueryExecutor? executor})
    : super(executor ?? NativeDatabase.memory());

  @override
  int get schemaVersion => 16;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(localNoteTags);
        await m.createTable(localTaskCompletions);
        await m.addColumn(tags, tags.updatedAt);
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
        await m.createTable(noteNodes);
        await m.addColumn(tasks, tasks.nodeId);
      }
      if (from < 14) {
        await customStatement('PRAGMA foreign_keys=OFF;');
        
        // Recreate note_nodes with REAL position
        await customStatement('''
          CREATE TABLE note_nodes_migration (
            id TEXT NOT NULL PRIMARY KEY,
            note_id TEXT NOT NULL REFERENCES notes (id),
            parent_id TEXT REFERENCES note_nodes (id),
            position REAL NOT NULL,
            type TEXT NOT NULL,
            data TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            deleted_at INTEGER,
            is_dirty INTEGER NOT NULL DEFAULT 1
          );
        ''');
        await customStatement('INSERT INTO note_nodes_migration SELECT id, note_id, parent_id, CAST(position AS REAL), type, data, created_at, updated_at, deleted_at, is_dirty FROM note_nodes;');
        await customStatement('DROP TABLE note_nodes;');
        await customStatement('ALTER TABLE note_nodes_migration RENAME TO note_nodes;');

        // Recreate tasks with REAL position
        await customStatement('''
          CREATE TABLE tasks_migration (
            id TEXT NOT NULL PRIMARY KEY,
            user_id TEXT NOT NULL,
            note_id TEXT NOT NULL,
            title TEXT NOT NULL,
            status TEXT NOT NULL,
            position REAL NOT NULL DEFAULT 0.0,
            recurrence TEXT,
            due_date INTEGER,
            completed_at INTEGER,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            deleted_at INTEGER,
            node_id TEXT REFERENCES note_nodes (id),
            is_dirty INTEGER NOT NULL DEFAULT 1
          );
        ''');
        await customStatement('INSERT INTO tasks_migration SELECT id, user_id, note_id, title, status, CAST(position AS REAL), recurrence, due_date, completed_at, created_at, updated_at, deleted_at, node_id, is_dirty FROM tasks;');
        await customStatement('DROP TABLE tasks;');
        await customStatement('ALTER TABLE tasks_migration RENAME TO tasks;');
        
        await customStatement('PRAGMA foreign_keys=ON;');
      }
      if (from < 15) {
        await customStatement('DELETE FROM notes WHERE is_inbox = 1;');
        await customStatement('ALTER TABLE notes DROP COLUMN is_inbox;');
      }
      if (from < 16) {
        await m.createTable(localYjsStates);
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
