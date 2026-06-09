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
          ..orderBy([
            (t) =>
                OrderingTerm(expression: t.updatedAt, mode: OrderingMode.desc)
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
  Future<NoteData?> getInboxNote() {
    return (select(notes)..where((t) => t.isInbox.equals(true)))
        .getSingleOrNull();
  }

  /// Streams the single inbox note, re-emitting whenever a new one is
  /// created.
  Stream<NoteData?> watchInboxNote() {
    return (select(notes)..where((t) => t.isInbox.equals(true)))
        .watchSingleOrNull();
  }

  /// Streams every active (non-archived, non-deleted) note attached to the
  /// given [contextId], newest first.
  Stream<List<NoteData>> watchNotesByContext(String contextId) {
    return (select(notes)
          ..where((t) => t.contextId.equals(contextId))
          ..where((t) => t.archived.equals(false))
          ..where((t) => t.deletedAt.isNull())
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
        title: excluded.title,
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

  /// Returns every note that has unsynced local changes.
  Future<List<NoteData>> getDirtyNotes() {
    return (select(notes)..where((t) => t.isDirty.equals(true))).get();
  }

  /// Flips the dirty flag off without touching any other field — the
  /// [updatedAt] stays exactly as the backend returned it so the next
  /// pull can detect remote edits.
  Future<void> clearDirtyFlag(String id) async {
    await (update(notes)..where((t) => t.id.equals(id)))
        .write(const NotesCompanion(isDirty: Value(false)));
  }

  /// Stores a note that came back from the backend. Uses
  /// [InsertMode.insertOrReplace] so a re-pulled row replaces the local
  /// copy in place, and always sets [isDirty] to `false` so the row does
  /// not get pushed back to the server.
  Future<void> upsertFromRemote(NoteData note) async {
    final incoming = note.copyWith(isDirty: false);
    await into(notes).insertOnConflictUpdate(incoming);
  }
}
