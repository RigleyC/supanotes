import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/local_note_documents.dart';
import '../tables/note_sync_errors.dart';
import '../tables/pending_note_operations.dart';

part 'note_operations_dao.g.dart';

@DriftAccessor(tables: [
  LocalNoteDocuments,
  PendingNoteOperations,
  NoteSyncErrors,
])
class NoteOperationsDao extends DatabaseAccessor<AppDatabase>
    with _$NoteOperationsDaoMixin {
  NoteOperationsDao(super.db);

  Stream<LocalNoteDocumentData?> watchNoteDocument(String noteId) {
    return (select(localNoteDocuments)
          ..where((t) => t.noteId.equals(noteId)))
        .watchSingleOrNull();
  }

  Future<void> upsertNoteDocument(LocalNoteDocumentsCompanion doc) {
    return into(localNoteDocuments).insert(
      doc,
      onConflict: DoUpdate((_) => doc),
    );
  }

  Future<void> deleteNoteDocument(String noteId) async {
    await (delete(localNoteDocuments)
          ..where((t) => t.noteId.equals(noteId)))
        .go();
  }

  Future<void> insertPendingOperation(PendingNoteOperationsCompanion op) {
    return into(pendingNoteOperations).insert(
      op,
      mode: InsertMode.insertOrReplace,
    );
  }

  Stream<List<PendingNoteOperationData>> watchPendingOperations(
    String noteId,
  ) {
    return (select(pendingNoteOperations)
          ..where((t) => t.noteId.equals(noteId))
          ..orderBy([(t) => OrderingTerm(expression: t.ordinal)]))
        .watch();
  }

  Future<List<PendingNoteOperationData>> getPendingOperations(
    String noteId,
  ) async {
    return (select(pendingNoteOperations)
          ..where((t) => t.noteId.equals(noteId))
          ..orderBy([(t) => OrderingTerm(expression: t.ordinal)]))
        .get();
  }

  Future<void> deletePendingOperation(String operationId) async {
    await (delete(pendingNoteOperations)
          ..where((t) => t.operationId.equals(operationId)))
        .go();
  }

  Future<void> deletePendingOperationsForNote(String noteId) async {
    await (delete(pendingNoteOperations)
          ..where((t) => t.noteId.equals(noteId)))
        .go();
  }

  Future<void> incrementAttempt(String operationId) async {
    final op = await (select(pendingNoteOperations)
          ..where((t) => t.operationId.equals(operationId)))
        .getSingleOrNull();
    if (op == null) return;
    await (update(pendingNoteOperations)
          ..where((t) => t.operationId.equals(operationId)))
        .write(
      PendingNoteOperationsCompanion(
        attemptCount: Value(op.attemptCount + 1),
        lastAttemptAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  Future<void> insertSyncError(NoteSyncErrorsCompanion error) {
    return into(noteSyncErrors).insert(
      error,
      mode: InsertMode.insertOrReplace,
    );
  }

  Stream<List<NoteSyncErrorData>> watchSyncErrors(String noteId) {
    return (select(noteSyncErrors)
          ..where((t) => t.noteId.equals(noteId))
          ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]))
        .watch();
  }

  Future<void> deleteSyncError(String operationId) async {
    await (delete(noteSyncErrors)
          ..where((t) => t.operationId.equals(operationId)))
        .go();
  }
}
