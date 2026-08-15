import 'package:drift/drift.dart';
import '../note_lifecycle_policy.dart';
import '../../../features/notes/catalog/model/note_strings.dart';
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
  bool collapseImages,
});

/// Derives a display title from note content by extracting the first non-empty
/// line and stripping markdown heading, task and list markers.
String deriveNoteTitle(String content) {
  final lines = content.split('\n');
  for (final line in lines) {
    var trimmed = line.trim();
    if (trimmed.isEmpty) continue;

    // Strip heading markers (# ## ###)
    trimmed = trimmed.replaceFirst(RegExp(r'^#+\s*'), '');
    // Strip task checkboxes (- [ ] - [x] * [ ] * [x])
    trimmed = trimmed.replaceFirst(RegExp(r'^[-*]\s*\[[ xX]\]\s*'), '');
    // Strip bullet list markers (- item * item)
    trimmed = trimmed.replaceFirst(RegExp(r'^[-*]\s*'), '');
    // Strip ordered list markers (1. item)
    trimmed = trimmed.replaceFirst(RegExp(r'^\d+\.\s*'), '');

    trimmed = trimmed.trim();
    if (trimmed.isEmpty) continue;
    return trimmed;
  }
  return NoteStrings.fallbackTitle;
}

const _noteSelectColumns =
    'SELECT n.*, '
    'COALESCE(unp.favorite, 0) AS favorite, '
    'COALESCE(unp.archived, 0) AS archived, '
    'COALESCE(unp.hide_completed, 0) AS hide_completed, '
    'COALESCE(unp.collapse_images, 0) AS collapse_images, '
    'n.content AS title';

@DriftAccessor(tables: [Notes, UserNotePreferences])
class NotesDao extends DatabaseAccessor<AppDatabase> with _$NotesDaoMixin {
  NotesDao(super.db);

  /// Streams all active notes with the user's preferences.
  Stream<List<NoteQueryResult>> watchAllActiveNotes(String userId) {
    return _watchWithPref(
      '$_noteSelectColumns '
      'FROM notes n '
      'LEFT JOIN user_note_preferences unp ON unp.note_id = n.id AND unp.user_id = ? '
      'WHERE COALESCE(unp.archived, 0) = 0 AND n.deleted_at IS NULL '
      "AND n.lifecycle_state <> '$emptyDraftLifecycleState' "
      'ORDER BY COALESCE(unp.favorite, 0) DESC, n.updated_at DESC, n.id DESC',
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
      readsFrom: {notes, userNotePreferences},
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
      readsFrom: {notes, userNotePreferences},
    ).watch().map((rows) {
      if (rows.isEmpty) return null;
      return _queryResultFromRow(rows.first);
    });
  }

  /// Streams every favorite note with the user's preferences.
  Stream<List<NoteQueryResult>> watchFavorites(String userId) {
    return _watchWithPref(
      '$_noteSelectColumns '
      'FROM notes n '
      'LEFT JOIN user_note_preferences unp ON unp.note_id = n.id AND unp.user_id = ? '
      'WHERE COALESCE(unp.favorite, 0) = 1 AND COALESCE(unp.archived, 0) = 0 AND n.deleted_at IS NULL '
      "AND n.lifecycle_state <> '$emptyDraftLifecycleState' "
      'ORDER BY n.updated_at DESC, n.id DESC',
      userId,
    );
  }

  NoteQueryResult? _queryResultFromRow(QueryRow row) {
    final id = row.read<String>('id');
    if (id.isEmpty) return null;
    final note = NoteData(
      id: id,
      userId: row.read<String>('user_id'),
      content: row.read<String>('content'),
      excerpt: row.read<String?>('excerpt'),
      createdAt: row.read<DateTime>('created_at'),
      updatedAt: row.read<DateTime>('updated_at'),
      deletedAt: row.read<DateTime?>('deleted_at'),
      isDirty: row.read<bool>('is_dirty'),
      hasRemoteCopy: row.read<bool>('has_remote_copy'),
      noteIconDirty: row.read<bool>('note_icon_dirty'),
      lifecycleState: row.read<String>('lifecycle_state'),
      permission: row.read<String?>('permission'),
      sharedByEmail: row.read<String?>('shared_by_email'),
      sharedByName: row.read<String?>('shared_by_name'),
      noteIconJson: row.read<String?>('note_icon_json'),
    );
    return (
      note: note,
      title: deriveNoteTitle(row.read<String>('content')),
      favorite: row.read<bool>('favorite'),
      archived: row.read<bool>('archived'),
      hideCompleted: row.read<bool>('hide_completed'),
      collapseImages: row.read<bool>('collapse_images'),
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
      readsFrom: {notes, userNotePreferences},
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
    return into(notes).insert(_withDerivedLifecycleState(note));
  }

  Future<void> upsertNote(NotesCompanion note) {
    final incoming = _withDerivedLifecycleState(note);
    return into(notes).insert(
      incoming,
      onConflict: DoUpdate.withExcluded(
        (old, excluded) => NotesCompanion.custom(
          content: excluded.content,
          excerpt: excluded.excerpt,
          updatedAt: excluded.updatedAt,
          isDirty: excluded.isDirty,
          lifecycleState: incoming.lifecycleState.present
              ? excluded.lifecycleState
              : old.lifecycleState,
        ),
      ),
    );
  }

  Future<void> updateNote(NotesCompanion note) async {
    await (update(notes)..where((t) => t.id.equals(note.id.value))).write(
      _withDerivedLifecycleState(note),
    );
  }

  /// Applies a remote snapshot only when the clean local row still has the
  /// version observed before the network request started.
  Future<bool> updateRemoteNoteIfUnchanged({
    required String id,
    required DateTime expectedUpdatedAt,
    required NotesCompanion note,
  }) async {
    final materializedNote = note.copyWith(
      lifecycleState: const Value(materializedLifecycleState),
    );
    final updatedRows =
        await (update(notes)..where(
              (t) =>
                  t.id.equals(id) &
                  t.deletedAt.isNull() &
                  t.isDirty.equals(false) &
                  t.updatedAt.equals(expectedUpdatedAt),
            ))
            .write(materializedNote);
    return updatedRows == 1;
  }

  /// Updates only the share metadata present in the remote catalog response.
  /// Pending local icon changes are preserved by leaving [noteIconDirty]
  /// untouched.
  Future<bool> updateRemoteShareMetadata({
    required String id,
    Value<String?> permission = const Value.absent(),
    Value<String?> sharedByEmail = const Value.absent(),
    Value<String?> sharedByName = const Value.absent(),
    Value<String?> noteIconJson = const Value.absent(),
  }) {
    return attachedDatabase.transaction(() async {
      final hasShareMetadata =
          permission.present || sharedByEmail.present || sharedByName.present;
      if (hasShareMetadata) {
        final updatedRows = await (update(notes)..where((t) => t.id.equals(id)))
            .write(
              NotesCompanion(
                permission: permission,
                sharedByEmail: sharedByEmail,
                sharedByName: sharedByName,
              ),
            );
        if (updatedRows != 1) return false;
        await attachedDatabase.noteLifecycleDao.markMaterialized(id);
      }

      if (!noteIconJson.present) return hasShareMetadata;

      // The write transaction makes this check and the icon update atomic with
      // the metadata refresh. A local icon mutation either wins before this
      // check or runs after this transaction and overwrites the remote value.
      final iconRows =
          await (update(notes)
                ..where((t) => t.id.equals(id) & t.noteIconDirty.equals(false)))
              .write(NotesCompanion(noteIconJson: noteIconJson));
      if (iconRows == 1) {
        await attachedDatabase.noteLifecycleDao.markMaterialized(id);
        return true;
      }
      if (hasShareMetadata) return true;

      // An icon-only update can be skipped because a local icon is pending.
      // Confirm that the row still exists so the caller can distinguish that
      // race from a note deleted while the catalog request was in flight.
      final row = await getNoteById(id);
      return row != null;
    });
  }

  /// Updates content, excerpt and updatedAt for a projected note in SQLite.
  Future<void> updateNoteProjection({
    required String id,
    required String content,
    String? excerpt,
    required bool materialized,
  }) async {
    final now = DateTime.now();
    await (update(notes)..where((t) => t.id.equals(id))).write(
      NotesCompanion(
        content: Value(content),
        excerpt: Value(excerpt),
        updatedAt: Value(now),
        lifecycleState: materialized
            ? const Value(materializedLifecycleState)
            : const Value.absent(),
      ),
    );
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
          ..where((t) => t.hasRemoteCopy.equals(true) | t.deletedAt.isNull()))
        .get();
  }

  /// Returns dirty tombstones for notes that are known to exist remotely.
  Future<List<NoteData>> getDirtyDeletedNotes() {
    return (select(notes)..where(
          (t) =>
              t.isDirty.equals(true) &
              t.deletedAt.isNotNull() &
              t.hasRemoteCopy.equals(true),
        ))
        .get();
  }

  /// Returns dirty tombstones for notes that only exist locally.
  Future<List<NoteData>> getDirtyLocalOnlyDeletedNotes() {
    return (select(notes)..where(
          (t) =>
              t.isDirty.equals(true) &
              t.deletedAt.isNotNull() &
              t.hasRemoteCopy.equals(false),
        ))
        .get();
  }

  /// Returns local rows that represent notes known to exist on the server.
  /// Used by catalog reconciliation to remove notes deleted on another device.
  Future<List<NoteData>> getRemoteNotes(String userId) {
    return (select(
          notes,
        )..where((t) => t.userId.equals(userId) & t.hasRemoteCopy.equals(true)))
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

  Future<List<NoteData>> getDirtyNoteIcons() {
    return (select(notes)..where((t) => t.noteIconDirty.equals(true))).get();
  }

  Future<void> clearNoteIconDirty(
    String id,
    DateTime pushedUpdatedAt, {
    required String? expectedNoteIconJson,
  }) async {
    await (update(notes)..where(
          (t) =>
              t.id.equals(id) &
              t.updatedAt.equals(pushedUpdatedAt) &
              (expectedNoteIconJson == null
                  ? t.noteIconJson.isNull()
                  : t.noteIconJson.equals(expectedNoteIconJson)),
        ))
        .write(const NotesCompanion(noteIconDirty: Value(false)));
  }

  /// Applies the remote icon when its note version is newer than a pending
  /// local icon mutation. Content dirtiness and its local timestamp remain
  /// untouched so the document sync can continue independently.
  Future<bool> resolveRemoteNoteIcon({
    required String id,
    required String? noteIconJson,
    required DateTime remoteUpdatedAt,
    required DateTime expectedUpdatedAt,
    required String? expectedNoteIconJson,
  }) async {
    return attachedDatabase.transaction(() async {
      final local = await getNoteById(id);
      if (local == null || !local.noteIconDirty) return false;

      // A local icon edited after the server version was fetched must remain
      // pending. The server timestamp is not a local mutation timestamp, so
      // it cannot win over a newer local row.
      if (local.updatedAt.isAfter(remoteUpdatedAt)) return false;

      final updated =
          await (update(notes)..where(
                (t) =>
                    t.id.equals(id) &
                    t.updatedAt.equals(expectedUpdatedAt) &
                    t.noteIconDirty.equals(true) &
                    (expectedNoteIconJson == null
                        ? t.noteIconJson.isNull()
                        : t.noteIconJson.equals(expectedNoteIconJson)),
              ))
              .write(
                NotesCompanion(
                  noteIconJson: Value(noteIconJson),
                  noteIconDirty: const Value(false),
                  updatedAt: local.isDirty
                      ? const Value.absent()
                      : Value(remoteUpdatedAt),
                ),
              );
      return updated > 0;
    });
  }

  /// Permanently removes a note from the local database.
  Future<void> hardDeleteNote(String id) async {
    await (delete(notes)..where((t) => t.id.equals(id))).go();
  }

  /// Stores a note that came back from the backend. Uses
  /// [InsertMode.insertOrReplace] so a re-pulled row replaces the local
  /// copy in place, and always sets [isDirty] to `false` so the row does
  /// not get pushed back to the server.
  Future<void> upsertFromRemote(NoteData note) async {
    final incoming = note.copyWith(
      isDirty: false,
      hasRemoteCopy: true,
      lifecycleState: materializedLifecycleState,
    );
    await into(notes).insertOnConflictUpdate(incoming);
  }

  NotesCompanion _withDerivedLifecycleState(NotesCompanion note) {
    final hasMeaningfulValue =
        (note.content.present && note.content.value.trim().isNotEmpty) ||
        (note.hasRemoteCopy.present && note.hasRemoteCopy.value);
    final hasMeaningfulMetadata =
        (note.noteIconJson.present && note.noteIconJson.value != null) ||
        (note.noteIconDirty.present && note.noteIconDirty.value);
    if (!hasMeaningfulValue && !hasMeaningfulMetadata) return note;
    return note.copyWith(
      lifecycleState: const Value(materializedLifecycleState),
    );
  }
}
