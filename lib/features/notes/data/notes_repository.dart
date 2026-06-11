import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../domain/note_model.dart';
import '../domain/task_entry.dart';
import '../../tasks/data/local/tasks_local_repository.dart';
import 'local/notes_local_repository.dart';

/// Presentation-facing facade over the local notes database.
///
/// Wraps the lower-level [NotesLocalRepository] and exposes operations
/// in terms of [NoteModel] so widgets never have to import Drift types.
/// Every mutation goes through here so the `isDirty` flag, the
/// `updatedAt` timestamp, and the inbox singleton invariant are
/// consistently maintained.
abstract class INotesRepository {
  Stream<List<NoteModel>> watchNotes({
    String? contextId,
    bool favoritesOnly = false,
  });
  Stream<NoteModel?> watchInbox();
  Stream<NoteModel?> watchNoteById(String id);
  Future<NoteModel?> getNoteById(String id);
  Future<NoteModel> upsertNote({
    required String id,
    String? title,
    String content = '',
    String? contextId,
  });
  Future<void> updateNote(
    String id, {
    String? title,
    String? content,
    bool? favorite,
    bool? archived,
    String? contextId,
  });
  Future<void> toggleFavorite(String id);
  Future<void> softDelete(String id);
  Future<NoteModel> ensureInbox();
  Future<void> appendToInbox(String text);
  Future<void> syncTasksFromDocument(String noteId, List<TaskEntry> tasks);
  Future<NoteModel> createLocalNote({required String id});
  Future<void> saveNoteSnapshot({
    required String id,
    required String title,
    required String content,
    required List<TaskEntry> tasks,
  });
  Future<void> deleteIfEmptyOrTombstone(String id);
  Future<void> markHasRemoteCopy(String id);
}

class NotesRepository implements INotesRepository {
  NotesRepository(this._local, this._tasksLocal);

  final NotesLocalRepository _local;
  final TasksLocalRepository _tasksLocal;

  /// Streams active (non-archived, non-deleted, non-inbox) notes, mapped
  /// to [NoteModel]. When [favoritesOnly] is true, the result is filtered
  /// to favorite notes; when [contextId] is non-null, the result is
  /// filtered to notes attached to that context. When both are set,
  /// [contextId] wins because it is a more restrictive index.
  @override
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
  @override
  Stream<NoteModel?> watchInbox() {
    return _local.watchInbox().map(
      (d) => d == null ? null : NoteModel.fromData(d),
    );
  }

  /// Streams a single note by id.
  @override
  Stream<NoteModel?> watchNoteById(String id) {
    return _local
        .watchNoteById(id)
        .map((d) => d == null ? null : NoteModel.fromData(d));
  }

  @override
  Future<NoteModel?> getNoteById(String id) async {
    final d = await _local.getNoteById(id);
    return d == null ? null : NoteModel.fromData(d);
  }

  /// Insert-or-update a note by [id]. When the row does not exist (lazy
  /// creation), a new row is created. When it does, only the provided
  /// fields are overwritten. Always marks the row as dirty so the next
  /// sync round pushes changes to the backend.
  @override
  Future<NoteModel> upsertNote({
    required String id,
    String? title,
    String content = '',
    String? contextId,
  }) async {
    final now = DateTime.now().toUtc();
    final companion = NotesCompanion(
      id: Value(id),
      userId: Value(_local.userId),
      title: Value(title),
      content: Value(content),
      contextId: Value(contextId),
      excerpt: Value(_excerptFrom(content)),
      createdAt: Value(now),
      updatedAt: Value(now),
      isDirty: const Value(true),
    );
    await _local.upsertNoteRaw(companion);
    final saved = await _local.getNoteById(id);
    return NoteModel.fromData(saved!);
  }

  /// Applies a partial update to the note with [id]. Only non-null
  /// arguments are written. Bumps `updatedAt` and re-flips `isDirty`
  /// so the change reaches the backend on the next sync round.
  @override
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
      contextId: contextId == null ? const Value.absent() : Value(contextId),
      updatedAt: Value(DateTime.now().toUtc()),
      isDirty: const Value(true),
    );
    await _local.updateNoteRaw(companion);
  }

  /// Flips the favorite flag on the given note. No-op if the row no
  /// longer exists (e.g. it was deleted in another tab).
  @override
  Future<void> toggleFavorite(String id) async {
    final current = await _local.getNoteById(id);
    if (current == null) return;
    await updateNote(id, favorite: !current.favorite);
  }

  /// Soft-deletes the note. The row stays in the database with
  /// `deletedAt` set so the tombstone reaches the backend on the next
  /// sync round; sync is the only thing that ever hard-deletes a row.
  @override
  Future<void> softDelete(String id) async {
    await _local.softDeleteNote(id);
  }

  @override
  Future<NoteModel> ensureInbox() async {
    final inbox = await _local.getOrCreateInboxNote();
    return NoteModel.fromData(inbox);
  }

  /// Appends [text] to the user's inbox note, creating the inbox row
  /// on first use. The new block is separated from the existing content
  /// by a blank line so distinct captures stay visually distinct.
  @override
  Future<void> appendToInbox(String text) async {
    final existing = await _local.getOrCreateInboxNote();
    final separator = existing.content.isEmpty ? '' : '\n\n';
    final newContent = '${existing.content}$separator$text';
    await _local.updateNoteContent(existing.id, newContent);
  }

  @override
  Future<NoteModel> createLocalNote({required String id}) async {
    final existing = await _local.getNoteById(id);
    if (existing != null) return NoteModel.fromData(existing);
    final created = await _local.createNoteWithId(id);
    return NoteModel.fromData(created);
  }

  @override
  Future<void> saveNoteSnapshot({
    required String id,
    required String title,
    required String content,
    required List<TaskEntry> tasks,
  }) async {
    await syncTasksFromDocument(id, tasks);
    final normalizedTitle = title.trim().isEmpty ? null : title;
    final current = await _local.getNoteById(id);
    if (current == null) return;

    await updateNote(
      id,
      title: normalizedTitle,
      content: content,
    );
  }

  @override
  Future<void> deleteIfEmptyOrTombstone(String id) async {
    final note = await _local.getNoteById(id);
    if (note == null) return;
    if (!_isTextEmpty(note)) return;

    final tasks = await _tasksLocal.getNoteTasks(id);
    if (tasks.isNotEmpty) return;

    if (note.hasRemoteCopy) {
      await _local.softDeleteNote(id);
    } else {
      await _local.hardDeleteNote(id);
    }
  }

  @override
  Future<void> markHasRemoteCopy(String id) {
    return _local.markHasRemoteCopy(id);
  }

  @override
  Future<void> syncTasksFromDocument(
    String noteId,
    List<TaskEntry> tasks,
  ) async {
    final currentTasks = await _tasksLocal.getNoteTasks(noteId);
    final currentIds = currentTasks.map((t) => t.id).toSet();
    final docIds = tasks.map((t) => t.id).toSet();

    for (final task in tasks) {
      if (currentIds.contains(task.id)) {
        await _tasksLocal.updateTask(
          TasksCompanion(
            id: Value(task.id),
            title: Value(task.text),
            status: Value(task.isComplete ? 'done' : 'pending'),
          ),
        );
      } else {
        await _tasksLocal.createTask(
          id: task.id,
          noteId: noteId,
          title: task.text,
          position: 0,
          status: task.isComplete ? 'done' : 'pending',
        );
      }
    }

    final removed = currentIds.difference(docIds);
    for (final id in removed) {
      await _tasksLocal.deleteTask(id);
    }
  }

  String? _excerptFrom(String content) {
    if (content.isEmpty) return null;
    final flat = content.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (flat.length <= 120) return flat;
    return '${flat.substring(0, 120)}…';
  }

  bool _isTextEmpty(NoteData note) {
    return (note.title == null || note.title!.trim().isEmpty) &&
        note.content.trim().isEmpty;
  }
}

/// Riverpod entry point for the feature-level [NotesRepository]. Reads
/// [notesLocalRepositoryProvider] which already gates on the signed-in
/// user, so this provider is itself safe to read only when authenticated.
final notesRepositoryProvider = Provider<INotesRepository>((ref) {
  final local = ref.watch(notesLocalRepositoryProvider);
  final tasksLocal = ref.watch(tasksLocalRepositoryProvider);
  return NotesRepository(local, tasksLocal);
});
