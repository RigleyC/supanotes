import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/auth/current_user.dart';
import '../../../../core/database/database.dart';
import '../../../../core/database/daos/notes_dao.dart';

final notesLocalRepositoryProvider = Provider<NotesLocalRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final userId = ref.watch(currentUserIdProvider)!;
  return NotesLocalRepository(db.notesDao, userId);
});

class NotesLocalRepository {
  NotesLocalRepository(this._dao, this._userId);

  final NotesDao _dao;
  final String _userId;
  final Uuid _uuid = const Uuid();

  /// User id this repository is bound to. Every note / inbox row
  /// created through this instance is stamped with this id so the
  /// `/sync/push` payload only contains the active user's data.
  String get userId => _userId;

  Stream<List<NoteData>> watchActiveNotes() {
    return _dao.watchAllActiveNotes();
  }

  Stream<List<NoteData>> watchNotesByContext(String contextId) {
    return _dao.watchNotesByContext(contextId);
  }

  Stream<List<NoteData>> watchFavorites() {
    return _dao.watchFavorites();
  }

  Stream<NoteData?> watchInbox() => _dao.watchInboxNote();

  Stream<NoteData?> watchNoteById(String id) => _dao.watchNoteById(id);

  Future<NoteData?> getNoteById(String id) {
    return _dao.getNoteById(id);
  }

  Future<NoteData> createNote() async {
    final now = DateTime.now().toUtc();
    final id = _uuid.v4();
    final companion = NotesCompanion.insert(
      id: id,
      userId: _userId,
      content: '',
      createdAt: now,
      updatedAt: now,
      isDirty: const Value(true),
    );
    await _dao.createNote(companion);
    return (await _dao.getNoteById(id))!;
  }

  /// Insert a fully-formed [NotesCompanion]. Used by the feature
  /// repository when it needs to set fields the default helper does
  /// not expose (title, excerpt, contextId).
  Future<void> createNoteRaw(NotesCompanion companion) {
    return _dao.createNote(companion);
  }

  /// Replace a note row with a partially-built [NotesCompanion].
  /// The caller is responsible for the field set and for bumping
  /// `updatedAt` / `isDirty`.
  Future<void> updateNoteRaw(NotesCompanion companion) {
    return _dao.updateNote(companion);
  }

  /// Soft-delete the row with [id]. Marks `deletedAt` and flips
  /// `isDirty` so the tombstone reaches the backend on the next sync.
  Future<void> softDeleteNote(String id) {
    return _dao.softDeleteNote(id);
  }

  Future<void> updateNoteContent(String id, String content) async {
    final note = await _dao.getNoteById(id);
    if (note == null) return;

    final companion = NotesCompanion(
      id: Value(id),
      content: Value(content),
      updatedAt: Value(DateTime.now().toUtc()),
      isDirty: const Value(true),
    );
    await _dao.updateNote(companion);
  }

  Future<NoteData> getOrCreateInboxNote() async {
    final existing = await _dao.getInboxNote();
    if (existing != null) return existing;

    final now = DateTime.now().toUtc();
    final id = _uuid.v4();
    final companion = NotesCompanion.insert(
      id: id,
      userId: _userId,
      content: '',
      isInbox: const Value(true),
      createdAt: now,
      updatedAt: now,
      isDirty: const Value(true),
    );
    await _dao.createNote(companion);
    return (await _dao.getNoteById(id))!;
  }
}
