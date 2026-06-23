import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/database/daos/note_links_dao.dart';
import '../../../core/database/daos/notes_dao.dart';
import '../../../core/database/daos/user_note_preferences_dao.dart';
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
    String content = '',
    String? contextId,
  });
  Future<void> updateNote(
    String id, {
    String? content,
    bool? collapseImages,
    String? contextId,
  });
  Future<void> toggleFavorite(String noteId);
  Future<void> softDelete(String id);
  Future<NoteModel> ensureInbox();
  Future<void> appendToInbox(String text);
  Future<void> syncTasksFromDocument(String noteId, List<TaskEntry> tasks);
  Future<NoteModel> createLocalNote({required String id});
  Future<void> saveNoteSnapshot({
    required String id,
    required String content,
    required List<TaskEntry> tasks,
  });
  Future<void> deleteIfEmptyOrTombstone(String id);
  Future<void> markHasRemoteCopy(String id);
}

class NotesRepository implements INotesRepository {
  NotesRepository(this._local, this._tasksLocal, this._prefsDao, [this._noteLinksDao]);

  final NotesLocalRepository _local;
  final TasksLocalRepository _tasksLocal;
  final UserNotePreferencesDao _prefsDao;
  final NoteLinksDao? _noteLinksDao;

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
    final Stream<List<NoteQueryResult>> source;
    if (contextId != null) {
      source = _local.watchNotesByContext(contextId);
    } else if (favoritesOnly) {
      source = _local.watchFavorites();
    } else {
      source = _local.watchActiveNotes();
    }
    return source.map((rows) => rows
        .map((qr) => NoteModel.fromQueryResult(qr))
        .toList());
  }

  /// Streams the single inbox note, if any. The inbox is a singleton
  /// per user — there is at most one row with `isInbox = true`.
  @override
  Stream<NoteModel?> watchInbox() {
    return _local.watchInbox().map(
      (qr) => qr == null ? null : NoteModel.fromQueryResult(qr),
    );
  }

  /// Streams a single note by id.
  @override
  Stream<NoteModel?> watchNoteById(String id) {
    return _local.watchNoteById(id).map(
      (qr) => qr == null ? null : NoteModel.fromQueryResult(qr),
    );
  }

  @override
  Future<NoteModel?> getNoteById(String id) async {
    final qr = await _local.getNoteById(id);
    return qr == null ? null : NoteModel.fromQueryResult(qr);
  }

  /// Insert-or-update a note by [id]. When the row does not exist (lazy
  /// creation), a new row is created. When it does, only the provided
  /// fields are overwritten. Always marks the row as dirty so the next
  /// sync round pushes changes to the backend.
  @override
  Future<NoteModel> upsertNote({
    required String id,
    String content = '',
    String? contextId,
  }) async {
    final now = DateTime.now().toUtc();
    final companion = NotesCompanion(
      id: Value(id),
      userId: Value(_local.userId),
      content: Value(content),
      contextId: Value(contextId),
      excerpt: Value(_excerptFrom(content)),
      createdAt: Value(now),
      updatedAt: Value(now),
      isDirty: const Value(true),
    );
    await _local.upsertNoteRaw(companion);
    final saved = await _local.getNoteById(id);
    return NoteModel.fromQueryResult(saved!);
  }

  /// Applies a partial update to the note with [id]. Only non-null
  /// arguments are written. Bumps `updatedAt` and re-flips `isDirty`
  /// so the change reaches the backend on the next sync round.
  @override
  Future<void> updateNote(
    String id, {
    String? content,
    bool? collapseImages,
    String? contextId,
  }) async {
    final current = await _local.getNoteById(id);
    if (current == null) return;

    final nextContent = content ?? current.note.content;
    final companion = NotesCompanion(
      id: Value(id),
      content: content == null ? const Value.absent() : Value(nextContent),
      excerpt: content == null
          ? const Value.absent()
          : Value(_excerptFrom(nextContent)),
      collapseImages:
          collapseImages == null ? const Value.absent() : Value(collapseImages),
      contextId: contextId == null ? const Value.absent() : Value(contextId),
      updatedAt: Value(DateTime.now().toUtc()),
      isDirty: const Value(true),
    );
    await _local.updateNoteRaw(companion);
  }

  /// Flips the favorite flag on the given note using the per-user
  /// preferences table. No-op if the row no longer exists.
  @override
  Future<void> toggleFavorite(String noteId) async {
    final current = await _local.getNoteById(noteId);
    if (current == null) return;
    await _prefsDao.setFavorite(_local.userId, noteId, !current.favorite);
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
    return NoteModel.fromQueryResult(inbox);
  }

  /// Appends [text] to the user's inbox note, creating the inbox row
  /// on first use. The new block is separated from the existing content
  /// by a blank line so distinct captures stay visually distinct.
  @override
  Future<void> appendToInbox(String text) async {
    final existing = await _local.getOrCreateInboxNote();
    final separator = existing.note.content.isEmpty ? '' : '\n\n';
    final newContent = '${existing.note.content}$separator$text';
    await _local.updateNoteContent(existing.note.id, newContent);
  }

  @override
  Future<NoteModel> createLocalNote({required String id}) async {
    final existing = await _local.getNoteById(id);
    if (existing != null) return NoteModel.fromQueryResult(existing);
    final created = await _local.createNoteWithId(id);
    return NoteModel.fromQueryResult(created);
  }

  @override
  Future<void> saveNoteSnapshot({
    required String id,
    required String content,
    required List<TaskEntry> tasks,
  }) async {
    final current = await _local.getNoteById(id);
    if (current == null) return;

    await syncTasksFromDocument(id, tasks);
    await updateNote(
      id,
      content: content,
    );
    await _syncNoteLinks(id, content);
  }

  Future<void> _syncNoteLinks(String sourceId, String content) async {
    final dao = _noteLinksDao;
    if (dao == null) return;

    final linkRegex = RegExp(
      r'note:\/\/([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})',
    );
    final matches = linkRegex.allMatches(content);
    final targetIds = matches.map((m) => m.group(1)!).toSet();

    final existingLinks = await dao.getLinksForNote(sourceId);
    final outboundLinks = existingLinks.where((l) => l.sourceId == sourceId).toList();
    final currentTargets = outboundLinks.map((l) => l.targetId).toSet();

    final toAdd = targetIds.difference(currentTargets);
    for (final targetId in toAdd) {
      await dao.createLink(sourceId: sourceId, targetId: targetId);
    }

    final toRemove = outboundLinks.where((l) => !targetIds.contains(l.targetId));
    for (final link in toRemove) {
      await dao.deleteLink(link.id);
    }
  }

  @override
  Future<void> deleteIfEmptyOrTombstone(String id) async {
    final qr = await _local.getNoteById(id);
    if (qr == null) return;
    if (!_isTextEmpty(qr.note)) return;

    final tasks = await _tasksLocal.getNoteTasks(id);
    if (tasks.isNotEmpty) return;

    if (qr.note.hasRemoteCopy) {
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
            status: Value(task.isComplete ? 'done' : 'open'),
          ),
        );
      } else {
        await _tasksLocal.createTask(
          id: task.id,
          noteId: noteId,
          title: task.text,
          position: 0,
          status: task.isComplete ? 'done' : 'open',
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
    final lines = content.split('\n');
    int firstNonEmptyIdx = -1;
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].trim().isNotEmpty) {
        firstNonEmptyIdx = i;
        break;
      }
    }
    if (firstNonEmptyIdx == -1) return null;
    final restOfLines = lines.skip(firstNonEmptyIdx + 1).join('\n');
    final flat = restOfLines.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (flat.isEmpty) return null;
    if (flat.length <= 120) return flat;
    return '${flat.substring(0, 120)}…';
  }

  bool _isTextEmpty(NoteData note) {
    return note.content.trim().isEmpty;
  }
}

/// Riverpod entry point for the feature-level [NotesRepository]. Reads
/// [notesLocalRepositoryProvider] which already gates on the signed-in
/// user, so this provider is itself safe to read only when authenticated.
final notesRepositoryProvider = Provider.autoDispose<INotesRepository>((ref) {
  final local = ref.watch(notesLocalRepositoryProvider);
  final tasksLocal = ref.watch(tasksLocalRepositoryProvider);
  final db = ref.watch(appDatabaseProvider);
  return NotesRepository(local, tasksLocal, db.userNotePreferencesDao, db.noteLinksDao);
});
