import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/database.dart';
import '../domain/note_model.dart';
import 'local/notes_local_repository.dart';

/// Presentation-facing facade over the local notes database.
///
/// Wraps the lower-level [NotesLocalRepository] and exposes operations
/// in terms of [NoteModel] so widgets never have to import Drift types.
/// Every mutation goes through here so the `isDirty` flag, the
/// `updatedAt` timestamp, and the inbox singleton invariant are
/// consistently maintained.
class NotesRepository {
  NotesRepository(this._local);

  final NotesLocalRepository _local;
  final Uuid _uuid = const Uuid();

  /// Streams active (non-archived, non-deleted, non-inbox) notes, mapped
  /// to [NoteModel]. When [favoritesOnly] is true, the result is filtered
  /// to favorite notes; when [contextId] is non-null, the result is
  /// filtered to notes attached to that context. When both are set,
  /// [contextId] wins because it is a more restrictive index.
  Stream<List<NoteModel>> watchNotes({
    String? contextId,
    bool favoritesOnly = false,
  }) {
    final Stream<List<NoteData>> source;
    if (contextId != null) {
      source = _local.watchNotesByContext(contextId);
    } else if (favoritesOnly) {
      source = _local.watchFavorites();
    } else {
      source = _local.watchActiveNotes();
    }
    return source.map((rows) => rows.map(NoteModel.fromData).toList());
  }

  /// Streams the single inbox note, if any. The inbox is a singleton
  /// per user — there is at most one row with `isInbox = true`.
  Stream<NoteModel?> watchInbox() {
    return _local.watchInbox().map((d) => d == null ? null : NoteModel.fromData(d));
  }

  /// Creates a new note and returns the freshly-saved row. Always marks
  /// the row as dirty so the next sync round pushes it to the backend.
  Future<NoteModel> createNote({
    String? title,
    String content = '',
    String? contextId,
  }) async {
    final now = DateTime.now().toUtc();
    final id = _uuid.v4();
    final companion = NotesCompanion.insert(
      id: id,
      userId: _local.userId,
      title: Value(title),
      content: content,
      contextId: Value(contextId),
      excerpt: Value(_excerptFrom(content)),
      createdAt: now,
      updatedAt: now,
      isDirty: const Value(true),
    );
    await _local.createNoteRaw(companion);
    final saved = await _local.getNoteById(id);
    return NoteModel.fromData(saved!);
  }

  /// Applies a partial update to the note with [id]. Only non-null
  /// arguments are written. Bumps `updatedAt` and re-flips `isDirty`
  /// so the change reaches the backend on the next sync round.
  Future<void> updateNote(
    String id, {
    String? title,
    String? content,
    bool? favorite,
    bool? archived,
    String? contextId,
  }) async {
    final current = await _local.getNoteById(id);
    if (current == null) return;

    final nextContent = content ?? current.content;
    final companion = NotesCompanion(
      id: Value(id),
      title: title == null ? const Value.absent() : Value(title),
      content: content == null ? const Value.absent() : Value(nextContent),
      excerpt: content == null
          ? const Value.absent()
          : Value(_excerptFrom(nextContent)),
      favorite: favorite == null ? const Value.absent() : Value(favorite),
      archived: archived == null ? const Value.absent() : Value(archived),
      contextId: contextId == null
          ? const Value.absent()
          : Value(contextId),
      updatedAt: Value(DateTime.now().toUtc()),
      isDirty: const Value(true),
    );
    await _local.updateNoteRaw(companion);
  }

  /// Flips the favorite flag on the given note. No-op if the row no
  /// longer exists (e.g. it was deleted in another tab).
  Future<void> toggleFavorite(String id) async {
    final current = await _local.getNoteById(id);
    if (current == null) return;
    await updateNote(id, favorite: !current.favorite);
  }

  /// Soft-deletes the note. The row stays in the database with
  /// `deletedAt` set so the tombstone reaches the backend on the next
  /// sync round; sync is the only thing that ever hard-deletes a row.
  Future<void> softDelete(String id) async {
    await _local.softDeleteNote(id);
  }

  /// Appends [text] to the user's inbox note, creating the inbox row
  /// on first use. The new block is separated from the existing content
  /// by a blank line so distinct captures stay visually distinct.
  Future<void> appendToInbox(String text) async {
    final existing = await _local.getOrCreateInboxNote();
    final separator = existing.content.isEmpty ? '' : '\n\n';
    final newContent = '${existing.content}$separator$text';
    await _local.updateNoteContent(existing.id, newContent);
  }

  String? _excerptFrom(String content) {
    if (content.isEmpty) return null;
    final flat = content.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (flat.length <= 120) return flat;
    return '${flat.substring(0, 120)}…';
  }
}

/// Riverpod entry point for the feature-level [NotesRepository]. Reads
/// [notesLocalRepositoryProvider] which already gates on the signed-in
/// user, so this provider is itself safe to read only when authenticated.
final notesRepositoryProvider = Provider<NotesRepository>((ref) {
  final local = ref.watch(notesLocalRepositoryProvider);
  return NotesRepository(local);
});
