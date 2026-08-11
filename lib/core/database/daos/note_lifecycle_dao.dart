import 'package:drift/drift.dart';

import '../database.dart';
import '../note_lifecycle_policy.dart';

/// Owns atomic local-note lifecycle decisions and aggregate deletion.
final class NoteLifecycleDao extends DatabaseAccessor<AppDatabase> {
  NoteLifecycleDao(super.db);

  Future<bool> discardLocalDraftIfUntouched(String noteId) {
    return attachedDatabase.transaction(() async {
      final matchingDraft = await customSelect(
        'SELECT n.id FROM notes n '
        'WHERE n.id = ? AND $untouchedLocalDraftPredicate',
        variables: [Variable.withString(noteId)],
      ).get();
      if (matchingDraft.isEmpty) return false;

      await _deleteNoteDataInTransaction(noteId);
      return true;
    });
  }

  Future<void> deleteNoteData(String noteId) {
    return attachedDatabase.transaction(
      () => _deleteNoteDataInTransaction(noteId),
    );
  }

  Future<void> _deleteNoteDataInTransaction(String noteId) async {
    final noteTasks = await (select(
      attachedDatabase.tasks,
    )..where((task) => task.noteId.equals(noteId))).get();
    for (final task in noteTasks) {
      await (delete(
        attachedDatabase.localTaskCompletions,
      )..where((completion) => completion.taskId.equals(task.id))).go();
    }

    await (delete(
      attachedDatabase.attachments,
    )..where((attachment) => attachment.noteId.equals(noteId))).go();
    await (delete(attachedDatabase.noteLinks)..where(
          (link) => link.sourceId.equals(noteId) | link.targetId.equals(noteId),
        ))
        .go();
    await (delete(
      attachedDatabase.userNotePreferences,
    )..where((preference) => preference.noteId.equals(noteId))).go();
    await (delete(
      attachedDatabase.tasks,
    )..where((task) => task.noteId.equals(noteId))).go();
    await (delete(
      attachedDatabase.localNoteDocuments,
    )..where((document) => document.noteId.equals(noteId))).go();
    await (delete(
      attachedDatabase.pendingNoteOperations,
    )..where((operation) => operation.noteId.equals(noteId))).go();
    await (delete(
      attachedDatabase.noteSyncErrors,
    )..where((error) => error.noteId.equals(noteId))).go();
    await (delete(
      attachedDatabase.syncSessions,
    )..where((session) => session.noteId.equals(noteId))).go();
    await (delete(
      attachedDatabase.notes,
    )..where((note) => note.id.equals(noteId))).go();
  }
}
