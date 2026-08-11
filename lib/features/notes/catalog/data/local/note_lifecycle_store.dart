import 'package:supanotes/core/database/database.dart';

abstract interface class NoteLifecycleStore {
  Future<bool> discardLocalDraft(String noteId);
}

final class DatabaseNoteLifecycleStore implements NoteLifecycleStore {
  const DatabaseNoteLifecycleStore(this._database);

  final AppDatabase _database;

  @override
  Future<bool> discardLocalDraft(String noteId) {
    return _database.noteLifecycleDao.discardLocalDraftIfUntouched(noteId);
  }
}
