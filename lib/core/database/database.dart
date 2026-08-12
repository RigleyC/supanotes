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
import 'daos/note_lifecycle_dao.dart';
import 'daos/note_operations_dao.dart';
import 'daos/notes_dao.dart';
import 'daos/task_completions_dao.dart';
import 'daos/tasks_dao.dart';
import 'daos/user_note_preferences_dao.dart';
import 'tables/attachments.dart';
import 'tables/local_note_documents.dart';
import 'tables/note_links.dart';
import 'tables/note_sync_errors.dart';
import 'tables/sync_sessions.dart';
import 'tables/notes.dart';
import 'tables/pending_note_operations.dart';
import 'tables/task_completions.dart';
import 'tables/tasks.dart';
import 'tables/user_note_preferences.dart';
import 'note_lifecycle_policy.dart';

import '../../features/tasks/domain/projected_task.dart';
import '../../features/tasks/domain/task_recurrence.dart'; // Needed for EnumNameConverter in tasks.dart

part 'database.g.dart';

sealed class RemoteNoteWriteMode {
  const RemoteNoteWriteMode();
}

final class InsertRemoteNote extends RemoteNoteWriteMode {
  const InsertRemoteNote();
}

final class UpdateRemoteNote extends RemoteNoteWriteMode {
  const UpdateRemoteNote({required this.expectedUpdatedAt});

  final DateTime expectedUpdatedAt;
}

@DriftDatabase(
  tables: [
    Notes,
    Tasks,
    LocalTaskCompletions,
    NoteLinks,
    Attachments,
    UserNotePreferences,
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

  late final noteLifecycleDao = NoteLifecycleDao(this);

  Future<void> clearAllData() async {
    await transaction(() async {
      for (final entity in allSchemaEntities) {
        if (entity is TableInfo) {
          await delete(entity).go();
        }
      }
    });
  }

  /// Removes all local projections and sync state for a deleted note.
  ///
  /// The note row is only the catalog entry. Its document, operations,
  /// projected tasks, task completions, links, preferences and attachments
  /// must be removed together so a deleted note cannot keep producing local
  /// results or notifications.
  Future<void> deleteNoteData(String noteId) async {
    await noteLifecycleDao.deleteNoteData(noteId);
  }

  /// Saves note content/excerpt projection and synced tasks in a single atomic transaction.
  /// [saveProjectedDocument] is the sole owner opening the transaction.
  Future<void> saveProjectedDocument({
    required String noteId,
    required String content,
    String? excerpt,
    required List<ProjectedTask> tasks,
    String userId = '',
  }) {
    return transaction(() async {
      await notesDao.updateNoteProjection(
        id: noteId,
        content: content,
        excerpt: excerpt,
        materialized: content.trim().isNotEmpty || tasks.isNotEmpty,
      );
      await tasksDao.syncProjectedTasksForNoteTyped(
        noteId,
        tasks,
        userId: userId,
      );
    });
  }

  /// Saves a remote note's canonical snapshot and every local projection atomically.
  /// [mode] describes whether the catalog observed a new note or a clean
  /// existing row. Returns `false` when a local edit or a concurrent deletion
  /// changed the row after the catalog read. In that case no part of the
  /// remote aggregate is written.
  Future<bool> saveRemoteNote({
    required String noteId,
    required RemoteNoteWriteMode mode,
    required NotesCompanion note,
    required LocalNoteDocumentsCompanion document,
    required List<ProjectedTask> tasks,
    String userId = '',
  }) {
    return transaction(() async {
      if (!note.id.present || note.id.value != noteId) {
        throw ArgumentError('Remote note companion id must match noteId');
      }
      if (!document.noteId.present || document.noteId.value != noteId) {
        throw ArgumentError('Remote document noteId must match noteId');
      }

      if (mode is InsertRemoteNote) {
        if (await notesDao.getNoteById(noteId) != null) return false;
        await notesDao.createNote(note);
      } else if (mode is UpdateRemoteNote) {
        if (!await notesDao.updateRemoteNoteIfUnchanged(
          id: noteId,
          expectedUpdatedAt: mode.expectedUpdatedAt,
          note: note,
        )) {
          return false;
        }
      } else {
        throw StateError('Unsupported remote note write mode');
      }

      await noteOperationsDao.upsertNoteDocument(document);
      await tasksDao.syncProjectedTasksForNoteTyped(
        noteId,
        tasks,
        userId: userId,
      );
      return true;
    });
  }

  @override
  int get schemaVersion => 28;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: _onUpgrade,
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  Future<void> _onUpgrade(Migrator m, int from, int to) async {
    await _migrateInitialSchema(m, from);
    await _migrateNoteFeatures(m, from);
    await _migrateTaskStorage(m, from);
    await _migrateSyncStorage(m, from);
    await _migrateNoteMetadata(m, from);
  }

  Future<bool> _hasColumn(String tableName, String columnName) async {
    final columns = await customSelect('PRAGMA table_info($tableName)').get();
    return columns.any((column) => column.data['name'] == columnName);
  }

  Future<void> _addColumnIfMissing(
    Migrator m,
    TableInfo table,
    String tableName,
    GeneratedColumn column,
  ) async {
    if (!await _hasColumn(tableName, column.$name)) {
      await m.addColumn(table, column);
    }
  }

  Future<void> _migrateInitialSchema(Migrator m, int from) async {
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
  }

  Future<void> _migrateNoteFeatures(Migrator m, int from) async {
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
  }

  Future<void> _migrateTaskStorage(Migrator m, int from) async {
    if (from < 14) {
      await customStatement('PRAGMA foreign_keys=ON;');
    }
    if (from < 15) {
      await customStatement('DELETE FROM notes WHERE is_inbox = 1;');
      await customStatement('ALTER TABLE notes DROP COLUMN is_inbox;');
    }
    if (from < 17) {
      await m.addColumn(tasks, tasks.hasTime);
    }
    if (from < 18) {
      await m.addColumn(tasks, tasks.reminder);
    }
    if (from < 19) {
      await customStatement('DROP TABLE IF EXISTS local_yjs_states;');
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
  }

  Future<void> _migrateSyncStorage(Migrator m, int from) async {
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
    if (from < 23) {
      await customStatement('DROP TABLE IF EXISTS local_yjs_states;');
    }
    if (from < 24) {
      await _migrateSyncOwnership(m, from);
    }
    if (from < 25 && from >= 21) {
      await _addColumnIfMissing(
        m,
        noteSyncErrors,
        'note_sync_errors',
        noteSyncErrors.ownerUserId,
      );
    }
  }

  Future<void> _migrateSyncOwnership(Migrator m, int from) async {
    if (from >= 21) {
      await _rebuildPendingOperations(m);
    }
    if (from >= 22) {
      await _addColumnIfMissing(
        m,
        syncSessions,
        'sync_sessions',
        syncSessions.ownerUserId,
      );
    }
  }

  Future<void> _rebuildPendingOperations(Migrator m) async {
    await _addColumnIfMissing(
      m,
      pendingNoteOperations,
      'pending_note_operations',
      pendingNoteOperations.ownerUserId,
    );
    await customStatement('''
      CREATE TABLE pending_note_operations_v24 (
        operation_id TEXT NOT NULL,
        note_id TEXT NOT NULL,
        owner_user_id TEXT,
        base_revision INTEGER NOT NULL,
        ordinal INTEGER NOT NULL,
        kind TEXT NOT NULL,
        block_id TEXT,
        payload_json TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        last_attempt_at INTEGER,
        attempt_count INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'pending',
        PRIMARY KEY (operation_id),
        UNIQUE (note_id, owner_user_id, ordinal)
      )
    ''');
    await customStatement('''
      INSERT INTO pending_note_operations_v24 (
        operation_id, note_id, owner_user_id, base_revision, ordinal,
        kind, block_id, payload_json, created_at, last_attempt_at,
        attempt_count, status
      )
      SELECT operation_id, note_id, owner_user_id, base_revision, ordinal,
        kind, block_id, payload_json, created_at, last_attempt_at,
        attempt_count, status
      FROM pending_note_operations
    ''');
    await customStatement('DROP TABLE pending_note_operations');
    await customStatement(
      'ALTER TABLE pending_note_operations_v24 '
      'RENAME TO pending_note_operations',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS '
      'idx_pending_ops_note_ordinal ON pending_note_operations(note_id, ordinal)',
    );
  }

  Future<void> _migrateNoteMetadata(Migrator m, int from) async {
    if (from < 26) {
      await _addColumnIfMissing(m, notes, 'notes', notes.noteIconJson);
    }
    if (from < 27) {
      await _addColumnIfMissing(m, notes, 'notes', notes.noteIconDirty);
    }
    if (from < 28) {
      await _addColumnIfMissing(m, notes, 'notes', notes.lifecycleState);
      await _materializeLifecycleStates();
    }
  }

  Future<void> _materializeLifecycleStates() async {
    await customStatement('''
      UPDATE notes
      SET lifecycle_state = '$materializedLifecycleState'
      WHERE has_remote_copy = 1
         OR TRIM(content) <> ''
         OR collapse_images = 1
         OR note_icon_json IS NOT NULL
         OR note_icon_dirty = 1
         OR EXISTS (
           SELECT 1 FROM tasks t
           WHERE t.note_id = notes.id AND t.deleted_at IS NULL
         )
         OR EXISTS (
           SELECT 1 FROM attachments a
           WHERE a.note_id = notes.id
         )
         OR EXISTS (
           SELECT 1 FROM user_note_preferences p
           WHERE p.note_id = notes.id
             AND (
               p.favorite = 1
               OR p.archived = 1
               OR p.hide_completed = 1
               OR p.filters <> '{}'
             )
         )
         OR EXISTS (
           SELECT 1 FROM local_note_documents d
           WHERE d.note_id = notes.id
         )
         OR EXISTS (
           SELECT 1 FROM pending_note_operations o
           WHERE o.note_id = notes.id
         )
         OR EXISTS (
           SELECT 1 FROM note_sync_errors e
           WHERE e.note_id = notes.id
         )
         OR EXISTS (
           SELECT 1 FROM sync_sessions s
           WHERE s.note_id = notes.id
         )
    ''');
  }
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
  ref.onDispose(db.close);
  return db;
});
