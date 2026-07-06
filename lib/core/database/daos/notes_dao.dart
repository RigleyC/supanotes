import 'package:drift/drift.dart';
import '../../../features/tasks/domain/task_recurrence.dart';
import '../../../features/notes/domain/note_strings.dart';
import '../database.dart';
import '../tables/notes.dart';
import '../tables/user_note_preferences.dart';

part 'notes_dao.g.dart';

typedef NoteQueryResult = ({
  NoteData note,
  String title,
  bool favorite,
  bool archived,
  bool hideCompleted,
});

/// SQL subselect that returns the plain text of the first non-deleted
/// note_nodes row with non-empty text, ordered by position. Used as the
/// note title everywhere notes are listed. Returns NULL when the note has
/// no text-bearing node; the Dart row reader applies the fallback.
const _titleFromNodesSubselect =
    "(SELECT nn.data->>'text' FROM note_nodes nn "
    "WHERE nn.note_id = n.id AND nn.deleted_at IS NULL "
    "AND nn.data->>'text' IS NOT NULL AND nn.data->>'text' <> '' "
    "ORDER BY nn.position ASC LIMIT 1) AS title";

const _noteSelectColumns = 'SELECT n.*, '
    'COALESCE(unp.favorite, 0) AS favorite, '
    'COALESCE(unp.archived, 0) AS archived, '
    'COALESCE(unp.hide_completed, 0) AS hide_completed, '
    '$_titleFromNodesSubselect';

typedef NoteWithTasksQueryResult = ({
  NoteQueryResult note,
  List<TaskData> tasks,
});

@DriftAccessor(tables: [Notes, UserNotePreferences])
class NotesDao extends DatabaseAccessor<AppDatabase> with _$NotesDaoMixin {
  NotesDao(super.db);

  /// Streams all active notes with the user's preferences.
  Stream<List<NoteQueryResult>> watchAllActiveNotes(String userId) {
    return _watchWithPref(
      '$_noteSelectColumns '
      'FROM notes n '
      'LEFT JOIN user_note_preferences unp ON unp.note_id = n.id AND unp.user_id = ? '
      'WHERE COALESCE(unp.archived, 0) = 0 AND n.deleted_at IS NULL AND n.is_inbox = 0 '
      'ORDER BY COALESCE(unp.favorite, 0) DESC, n.updated_at DESC',
      userId,
    );
  }

  /// Returns a [NoteData] row without preference info. Prefer
  /// [getNoteWithPrefsById] when the caller needs favorite/archived flags.
  Future<NoteData?> getNoteById(String id) async {
    return (select(notes)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  /// Returns a note with the user's preference flags, or `null` when the
  /// note does not exist.
  Future<NoteQueryResult?> getNoteWithPrefsById(
    String id,
    String userId,
  ) async {
    return customSelect(
      '$_noteSelectColumns '
      'FROM notes n '
      'LEFT JOIN user_note_preferences unp ON unp.note_id = n.id AND unp.user_id = ? '
      'WHERE n.id = ?',
      variables: [Variable.withString(userId), Variable.withString(id)],
      readsFrom: {notes, userNotePreferences, attachedDatabase.noteNodes},
    ).get().then(
      (rows) => rows.isEmpty ? null : _queryResultFromRow(rows.first),
    );
  }

  /// Streams a single note by id with the user's preferences.
  Stream<NoteQueryResult?> watchNoteById(String id, String userId) {
    return customSelect(
      '$_noteSelectColumns '
      'FROM notes n '
      'LEFT JOIN user_note_preferences unp ON unp.note_id = n.id AND unp.user_id = ? '
      'WHERE n.id = ?',
      variables: [Variable.withString(userId), Variable.withString(id)],
      readsFrom: {notes, userNotePreferences, attachedDatabase.noteNodes},
    ).watch().map((rows) {
      if (rows.isEmpty) return null;
      return _queryResultFromRow(rows.first);
    });
  }

  /// Returns the first inbox note (the spec says there is exactly one) or
  /// `null` if none has been created yet.
  Future<NoteQueryResult?> getInboxNote(String userId) {
    return customSelect(
      '$_noteSelectColumns '
      'FROM notes n '
      'LEFT JOIN user_note_preferences unp ON unp.note_id = n.id AND unp.user_id = ? '
      'WHERE n.user_id = ? AND n.is_inbox = 1 AND n.deleted_at IS NULL',
      variables: [Variable.withString(userId), Variable.withString(userId)],
      readsFrom: {notes, userNotePreferences, attachedDatabase.noteNodes},
    ).get().then(
      (rows) => rows.isEmpty ? null : _queryResultFromRow(rows.first),
    );
  }

  /// Streams the single inbox note, re-emitting whenever a new one is
  /// created.
  Stream<NoteQueryResult?> watchInboxNote(String userId) {
    return customSelect(
      '$_noteSelectColumns '
      'FROM notes n '
      'LEFT JOIN user_note_preferences unp ON unp.note_id = n.id AND unp.user_id = ? '
      'WHERE n.user_id = ? AND n.is_inbox = 1 AND n.deleted_at IS NULL',
      variables: [Variable.withString(userId), Variable.withString(userId)],
      readsFrom: {notes, userNotePreferences, attachedDatabase.noteNodes},
    ).watchSingleOrNull().map(
      (row) => row != null ? _queryResultFromRow(row) : null,
    );
  }

  /// Streams a note with its tasks in a single reactive emission via a
  /// LEFT JOIN. Drift re-executes the query whenever the `notes`, `tasks`
  /// or `user_note_preferences` tables change, so the combined stream
  /// stays in sync without manual stream merging.
  Stream<NoteWithTasksQueryResult?> watchNoteWithTasks(
    String id,
    String userId,
  ) {
    return customSelect(
      '$_noteSelectColumns, '
      't.id AS task_id, t.user_id AS task_user_id, t.note_id AS task_note_id, '
      't.title AS task_title, t.status AS task_status, '
      't.position AS task_position, '
      't.due_date AS task_due_date, t.recurrence AS task_recurrence, '
      't.completed_at AS task_completed_at, '
      't.created_at AS task_created_at, '
      't.updated_at AS task_updated_at, '
      't.deleted_at AS task_deleted_at '
      'FROM notes n '
      'LEFT JOIN tasks t ON t.note_id = n.id AND t.deleted_at IS NULL '
      'LEFT JOIN user_note_preferences unp '
      '  ON unp.note_id = n.id AND unp.user_id = ? '
      'WHERE n.id = ?',
      variables: [Variable.withString(userId), Variable.withString(id)],
      readsFrom: {notes, attachedDatabase.tasks, userNotePreferences, attachedDatabase.noteNodes},
    ).watch().map((rows) {
      if (rows.isEmpty) return null;
      return _noteWithTasksFromRows(rows);
    });
  }

  /// Streams every active note attached to the given [contextId] with
  /// the user's preferences.
  Stream<List<NoteQueryResult>> watchNotesByContext(
    String contextId,
    String userId,
  ) {
    return _watchWithPref(
      '$_noteSelectColumns '
      'FROM notes n '
      'LEFT JOIN user_note_preferences unp ON unp.note_id = n.id AND unp.user_id = ? '
      'WHERE n.context_id = ? AND COALESCE(unp.archived, 0) = 0 AND n.deleted_at IS NULL '
      'ORDER BY n.updated_at DESC',
      userId,
      extraVariables: [Variable.withString(contextId)],
    );
  }

  /// Streams every favorite note with the user's preferences.
  Stream<List<NoteQueryResult>> watchFavorites(String userId) {
    return _watchWithPref(
      '$_noteSelectColumns '
      'FROM notes n '
      'LEFT JOIN user_note_preferences unp ON unp.note_id = n.id AND unp.user_id = ? '
      'WHERE COALESCE(unp.favorite, 0) = 1 AND COALESCE(unp.archived, 0) = 0 AND n.deleted_at IS NULL '
      'ORDER BY n.updated_at DESC',
      userId,
    );
  }

  NoteQueryResult? _queryResultFromRow(QueryRow row) {
    final id = row.read<String>('id');
    if (id.isEmpty) return null;
    final note = NoteData(
      id: id,
      userId: row.read<String>('user_id'),
      contextId: row.read<String?>('context_id'),
      content: row.read<String>('content'),
      excerpt: row.read<String?>('excerpt'),
      isInbox: row.read<bool>('is_inbox'),
      embeddingStatus: row.read<String?>('embedding_status'),
      createdAt: row.read<DateTime>('created_at'),
      updatedAt: row.read<DateTime>('updated_at'),
      deletedAt: row.read<DateTime?>('deleted_at'),
      isDirty: row.read<bool>('is_dirty'),
      hasRemoteCopy: row.read<bool>('has_remote_copy'),
      collapseImages: row.read<bool>('collapse_images'),
      permission: row.read<String?>('permission'),
      sharedByEmail: row.read<String?>('shared_by_email'),
      sharedByName: row.read<String?>('shared_by_name'),
    );
    return (
      note: note,
      title: row.read<String?>('title') ?? NoteStrings.fallbackTitle,
      favorite: row.read<bool>('favorite'),
      archived: row.read<bool>('archived'),
      hideCompleted: row.read<bool>('hide_completed'),
    );
  }

  NoteWithTasksQueryResult _noteWithTasksFromRows(List<QueryRow> rows) {
    final first = rows.first;
    final note = _queryResultFromRow(first)!;
    final tasks = <TaskData>[];
    for (final row in rows) {
      final taskId = row.read<String?>('task_id');
      if (taskId == null || taskId.isEmpty) continue;
      tasks.add(_taskDataFromRow(row));
    }
    return (note: note, tasks: tasks);
  }

  TaskData _taskDataFromRow(QueryRow row) {
    final recurrenceRaw = row.read<String?>('task_recurrence');
    return TaskData(
      id: row.read<String>('task_id'),
      userId: row.read<String>('task_user_id'),
      noteId: row.read<String>('task_note_id'),
      title: row.read<String>('task_title'),
      status: row.read<String>('task_status'),
      position: row.read<double>('task_position'),
      dueDate: row.read<DateTime?>('task_due_date'),
      recurrence: recurrenceRaw != null
          ? TaskRecurrence.values.byName(recurrenceRaw)
          : null,
      completedAt: row.read<DateTime?>('task_completed_at'),
      createdAt: row.read<DateTime>('task_created_at'),
      updatedAt: row.read<DateTime>('task_updated_at'),
      deletedAt: row.read<DateTime?>('task_deleted_at'),
      isDirty: true,
    );
  }

  Stream<List<NoteQueryResult>> _watchWithPref(
    String sql,
    String userId, {
    List<Variable<Object>> extraVariables = const [],
  }) {
    return customSelect(
      sql,
      variables: [Variable.withString(userId), ...extraVariables],
      readsFrom: {notes, userNotePreferences, attachedDatabase.noteNodes},
    ).watch().map((rows) {
      final result = <NoteQueryResult>[];
      for (final row in rows) {
        final qr = _queryResultFromRow(row);
        if (qr != null) {
          result.add(qr);
        }
      }
      return result;
    });
  }

  Future<void> createNote(NotesCompanion note) {
    return into(notes).insert(note);
  }

  Future<void> upsertNote(NotesCompanion note) {
    return into(notes).insert(
      note,
      onConflict: DoUpdate.withExcluded(
        (old, excluded) => NotesCompanion.custom(
          content: excluded.content,
          contextId: excluded.contextId,
          excerpt: excluded.excerpt,
          updatedAt: excluded.updatedAt,
          isDirty: excluded.isDirty,
        ),
      ),
    );
  }

  Future<void> updateNote(NotesCompanion note) async {
    await (update(notes)..where((t) => t.id.equals(note.id.value))).write(note);
  }

  /// Marks [id] as soft-deleted (sets [NotesTable.deletedAt] to "now" and
  /// flips [NotesTable.isDirty] on so the next sync round propagates the
  /// tombstone). The row stays in the table — sync is the only thing that
  /// removes it for good.
  Future<void> softDeleteNote(String id) async {
    await (update(notes)..where((t) => t.id.equals(id))).write(
      NotesCompanion(
        deletedAt: Value(DateTime.now().toUtc()),
        isDirty: const Value(true),
      ),
    );
  }



  /// Returns every note that has unsynced local changes and is eligible for
  /// sync (has a remote copy, is inbox, or has non-empty content).
  /// Locally-created-then-deleted notes without a remote copy are excluded
  /// to avoid wasted API calls.
  Future<List<NoteData>> getDirtyNotes() {
    return (select(notes)
          ..where((t) => t.isDirty.equals(true))
          ..where(
            (t) =>
                t.hasRemoteCopy.equals(true) |
                t.isInbox.equals(true) |
                t.deletedAt.isNull(),
          ))
        .get();
  }

  /// Flips the dirty flag off only if the row's [updatedAt] still matches
  /// [pushedUpdatedAt] — if the user edited while the push was in flight
  /// the flag stays on so the next sync round picks up the new change.
  Future<void> clearDirtyFlag(String id, DateTime pushedUpdatedAt) async {
    await (update(notes)
          ..where((t) => t.id.equals(id) & t.updatedAt.equals(pushedUpdatedAt)))
        .write(const NotesCompanion(isDirty: Value(false)));
  }

  /// Permanently removes a note from the local database.
  Future<void> hardDeleteNote(String id) async {
    await (delete(notes)..where((t) => t.id.equals(id))).go();
  }

  /// Marks that the server holds a copy of this note so future sync
  /// rounds know it can be pushed.
  Future<void> markHasRemoteCopy(String id) async {
    await (update(notes)..where((t) => t.id.equals(id))).write(
      const NotesCompanion(hasRemoteCopy: Value(true)),
    );
  }

  /// Stores a note that came back from the backend. Uses
  /// [InsertMode.insertOrReplace] so a re-pulled row replaces the local
  /// copy in place, and always sets [isDirty] to `false` so the row does
  /// not get pushed back to the server.
  Future<void> upsertFromRemote(NoteData note) async {
    final incoming = note.copyWith(isDirty: false, hasRemoteCopy: true);
    await into(notes).insertOnConflictUpdate(incoming);
  }
}
