import 'package:drift/drift.dart';
import '../database.dart';
import '../tables/notes.dart';

part 'notes_dao.g.dart';

@DriftAccessor(tables: [Notes])
class NotesDao extends DatabaseAccessor<AppDatabase> with _$NotesDaoMixin {
  NotesDao(super.db);

  Stream<List<NoteData>> watchAllActiveNotes() {
    return (select(notes)
          ..where((t) => t.archived.equals(false))
          ..where((t) => t.deletedAt.isNull())
          ..where((t) => t.isInbox.equals(false))
          ..where(_nonEmptyNote)
          ..orderBy([
            (t) =>
                OrderingTerm(expression: t.favorite, mode: OrderingMode.desc),
            (t) =>
                OrderingTerm(expression: t.updatedAt, mode: OrderingMode.desc),
          ]))
        .watch();
  }

  Future<NoteData?> getNoteById(String id) async {
    return (select(notes)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Stream<NoteData?> watchNoteById(String id) {
    return (select(notes)..where((t) => t.id.equals(id))).watchSingleOrNull();
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

  /// Streams every active (non-archived, non-deleted) note attached to the
  /// given [contextId], newest first.
  Stream<List<NoteData>> watchNotesByContext(String contextId) {
    return (select(notes)
          ..where((t) => t.contextId.equals(contextId))
          ..where((t) => t.archived.equals(false))
          ..where((t) => t.deletedAt.isNull())
          ..where(_nonEmptyNote)
          ..orderBy([
            (t) =>
                OrderingTerm(expression: t.updatedAt, mode: OrderingMode.desc),
          ]))
        .watch();
  }

  /// Streams every active note that the user has marked as favorite,
  /// newest first.
  Stream<List<NoteData>> watchFavorites() {
    return (select(notes)
          ..where((t) => t.favorite.equals(true))
          ..where((t) => t.archived.equals(false))
          ..where((t) => t.deletedAt.isNull())
          ..where(_nonEmptyNote)
          ..orderBy([
            (t) =>
                OrderingTerm(expression: t.updatedAt, mode: OrderingMode.desc),
          ]))
        .watch();
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
        hideCompleted: excluded.hideCompleted,
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
