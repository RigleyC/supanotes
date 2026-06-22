import 'package:drift/drift.dart';
import '../database.dart';
import '../tables/notes.dart';
import '../tables/user_note_preferences.dart';

part 'notes_dao.g.dart';

@DriftAccessor(tables: [Notes, UserNotePreferences])
class NotesDao extends DatabaseAccessor<AppDatabase> with _$NotesDaoMixin {
  NotesDao(super.db);

  /// Streams all active notes with the user's hideCompleted preference.
  Stream<List<(NoteData, bool)>> watchAllActiveNotes(String userId) {
    return _watchWithPref(
      'SELECT n.*, COALESCE(unp.hide_completed, 0) AS resolved_hide_completed '
      'FROM notes n '
      'LEFT JOIN user_note_preferences unp ON unp.note_id = n.id AND unp.user_id = ? '
      'WHERE n.archived = 0 AND n.deleted_at IS NULL AND n.is_inbox = 0 AND trim(n.content) <> \'\' '
      'ORDER BY n.favorite DESC, n.updated_at DESC',
      userId,
    );
  }

  Future<NoteData?> getNoteById(String id) async {
    return (select(notes)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  /// Streams a single note by id with the user's hideCompleted preference.
  Stream<(NoteData?, bool)> watchNoteById(String id, String userId) {
    return customSelect(
      'SELECT n.*, COALESCE(unp.hide_completed, 0) AS resolved_hide_completed '
      'FROM notes n '
      'LEFT JOIN user_note_preferences unp ON unp.note_id = n.id AND unp.user_id = ? '
      'WHERE n.id = ?',
      variables: [Variable.withString(userId), Variable.withString(id)],
      readsFrom: {notes, userNotePreferences},
    ).watch().map((rows) {
      if (rows.isEmpty) return (null, false);
      final row = rows.first;
      final note = _noteFromRow(row);
      return (note, row.read<bool>('resolved_hide_completed'));
    });
  }

  /// Returns the first inbox note (the spec says there is exactly one) or
  /// `null` if none has been created yet.
  Future<NoteData?> getInboxNote(String userId) {
    return (select(notes)
          ..where((t) => t.userId.equals(userId))
          ..where((t) => t.isInbox.equals(true))
          ..where((t) => t.deletedAt.isNull()))
        .getSingleOrNull();
  }

  /// Streams the single inbox note, re-emitting whenever a new one is
  /// created.
  Stream<NoteData?> watchInboxNote(String userId) {
    return (select(notes)
          ..where((t) => t.userId.equals(userId))
          ..where((t) => t.isInbox.equals(true))
          ..where((t) => t.deletedAt.isNull()))
        .watchSingleOrNull();
  }

  /// Streams every active note attached to the given [contextId] with
  /// the user's hideCompleted preference.
  Stream<List<(NoteData, bool)>> watchNotesByContext(
      String contextId, String userId) {
    return _watchWithPref(
      'SELECT n.*, COALESCE(unp.hide_completed, 0) AS resolved_hide_completed '
      'FROM notes n '
      'LEFT JOIN user_note_preferences unp ON unp.note_id = n.id AND unp.user_id = ? '
      'WHERE n.context_id = ? AND n.archived = 0 AND n.deleted_at IS NULL AND trim(n.content) <> \'\' '
      'ORDER BY n.updated_at DESC',
      userId,
      extraVariables: [Variable.withString(contextId)],
    );
  }

  /// Streams every favorite note with the user's hideCompleted preference.
  Stream<List<(NoteData, bool)>> watchFavorites(String userId) {
    return _watchWithPref(
      'SELECT n.*, COALESCE(unp.hide_completed, 0) AS resolved_hide_completed '
      'FROM notes n '
      'LEFT JOIN user_note_preferences unp ON unp.note_id = n.id AND unp.user_id = ? '
      'WHERE n.favorite = 1 AND n.archived = 0 AND n.deleted_at IS NULL AND trim(n.content) <> \'\' '
      'ORDER BY n.updated_at DESC',
      userId,
    );
  }

  NoteData? _noteFromRow(QueryRow row) {
    final id = row.read<String>('id');
    if (id.isEmpty) return null;
    return NoteData(
      id: id,
      userId: row.read<String>('user_id'),
      contextId: row.read<String?>('context_id'),
      content: row.read<String>('content'),
      excerpt: row.read<String?>('excerpt'),
      isInbox: row.read<bool>('is_inbox'),
      favorite: row.read<bool>('favorite'),
      archived: row.read<bool>('archived'),
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
  }

  Stream<List<(NoteData, bool)>> _watchWithPref(
    String sql,
    String userId, {
    List<Variable<Object>> extraVariables = const [],
  }) {
    return customSelect(
      sql,
      variables: [Variable.withString(userId), ...extraVariables],
      readsFrom: {notes, userNotePreferences},
    ).watch().map((rows) {
      final result = <(NoteData, bool)>[];
      for (final row in rows) {
        final note = _noteFromRow(row);
        if (note != null) {
          result.add((note, row.read<bool>('resolved_hide_completed')));
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
      onConflict: DoUpdate.withExcluded((old, excluded) => NotesCompanion.custom(
        content: excluded.content,
        contextId: excluded.contextId,
        excerpt: excluded.excerpt,
        updatedAt: excluded.updatedAt,
        isDirty: excluded.isDirty,
      )),
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

  /// Shared filter: a note is non-empty when its trimmed content is not
  /// blank. Used to hide empty local-only notes from lists and to
  /// determine sync eligibility.
  Expression<bool> Function($NotesTable) get _nonEmptyNote =>
      (t) => CustomExpression<bool>(
            "trim(content) <> ''",
          );

  /// Returns every note that has unsynced local changes and is eligible for
  /// sync (has a remote copy, is inbox, or has non-empty content).
  /// Locally-created-then-deleted notes without a remote copy are excluded
  /// to avoid wasted API calls.
  Future<List<NoteData>> getDirtyNotes() {
    return (select(notes)
          ..where((t) => t.isDirty.equals(true))
          ..where(
            (t) => t.hasRemoteCopy.equals(true) |
                t.isInbox.equals(true) |
                _nonEmptyNote(t),
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
