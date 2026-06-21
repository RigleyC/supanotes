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
import 'tables/attachments.dart';
import 'tables/contexts.dart';
import 'tables/note_links.dart';
import 'tables/note_tags.dart';
import 'tables/notes.dart';
import 'tables/tags.dart';
import 'tables/task_completions.dart';
import 'tables/tasks.dart';

import '../../features/tasks/domain/task_recurrence.dart'; // Needed for EnumNameConverter in tasks.dart

part 'database.g.dart';

@DriftDatabase(
  tables: [Notes, Tasks, Contexts, Tags, LocalNoteTags, LocalTaskCompletions, NoteLinks, Attachments],
  daos: [NotesDao, ContextsDao, TasksDao, TagsDao, TaskCompletionsDao, NoteLinksDao, NoteTagsDao, AttachmentsDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.test({QueryExecutor? executor})
      : super(executor ?? NativeDatabase.memory());

  /// Latest schema version. Bumped to `10` — v10 adds collapseImages.
  @override
  int get schemaVersion => 10;

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
            await m.addColumn(notes, notes.hideCompleted);
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
              dev.log('Failed to drop note title column during migration: $e', name: 'DatabaseMigration');
            }
          }
          if (from < 9) {
            await m.createTable(attachments);
          }
          if (from < 10) {
            await m.addColumn(notes, notes.collapseImages);
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
