import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'daos/contexts_dao.dart';
import 'daos/notes_dao.dart';
import 'daos/tags_dao.dart';
import 'daos/task_completions_dao.dart';
import 'daos/tasks_dao.dart';
import 'tables/contexts.dart';
import 'tables/note_tags.dart';
import 'tables/notes.dart';
import 'tables/tags.dart';
import 'tables/task_completions.dart';
import 'tables/tasks.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [Notes, Tasks, Contexts, Tags, LocalNoteTags, LocalTaskCompletions],
  daos: [NotesDao, ContextsDao, TasksDao, TagsDao, TaskCompletionsDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Latest schema version. Bumped to `3` — the v2 wave added the
  /// `local_note_tags` and `local_task_completions` tables, the
  /// `updated_at` column on `tags`, and the `completed_at` column on
  /// `tasks`; v3 adds the `has_remote_copy` column on `notes`.
  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // v1 → v2: introduce the v2-only tables and add the
            // missing columns on existing tables.
            await m.createTable(localNoteTags);
            await m.createTable(localTaskCompletions);
            await m.addColumn(tags, tags.updatedAt);
            await m.addColumn(tasks, tasks.completedAt);
          }
          if (from < 3) {
            await m.addColumn(notes, notes.hasRemoteCopy);
          }
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
