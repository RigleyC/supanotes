import 'package:supanotes/core/database/database.dart';

abstract interface class NoteLifecycleStore {
  Future<void> discardLocalDraft(String noteId);
}

final class DatabaseNoteLifecycleStore implements NoteLifecycleStore {
  const DatabaseNoteLifecycleStore(this._database);

  final AppDatabase _database;

  @override
  Future<void> discardLocalDraft(String noteId) async {
    await _database.discardLocalDraftIfUntouched(noteId);
  }
}
