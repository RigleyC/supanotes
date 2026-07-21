import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/local_note_documents.dart';
import '../tables/note_sync_errors.dart';
import '../tables/pending_note_operations.dart';
import '../tables/sync_sessions.dart';


part 'note_operations_dao.g.dart';

@DriftAccessor(tables: [
  LocalNoteDocuments,
  PendingNoteOperations,
  NoteSyncErrors,
  SyncSessions,
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
    String noteId, {
    String? status,
  }) async {
    final query = select(pendingNoteOperations)
      ..where((t) => t.noteId.equals(noteId))
      ..orderBy([(t) => OrderingTerm(expression: t.ordinal)]);
    if (status != null) {
      query.where((t) => t.status.equals(status));
    }
    return query.get();
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

  Future<void> deleteStalePendingOps(String noteId, int minBaseRevision) async {
    await (delete(pendingNoteOperations)
          ..where((t) =>
              t.noteId.equals(noteId) &
              t.baseRevision.isSmallerThanValue(minBaseRevision)))
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

  // ---- Sync session CRUD ----

  Future<SyncSessionData?> getSyncSession(String noteId) {
    return (select(syncSessions)
          ..where((t) => t.noteId.equals(noteId)))
        .getSingleOrNull();
  }

  Future<void> upsertSyncSession(SyncSessionsCompanion session) {
    return into(syncSessions).insert(
      session,
      onConflict: DoUpdate((_) => session),
    );
  }

  Future<void> deleteSyncSession(String noteId) async {
    await (delete(syncSessions)
          ..where((t) => t.noteId.equals(noteId)))
        .go();
  }

  // ---- Outbox status ----

  Future<void> updatePendingOpsStatus(
    String noteId,
    String fromStatus,
    String toStatus,
  ) async {
    await (update(pendingNoteOperations)
          ..where((t) => t.noteId.equals(noteId) & t.status.equals(fromStatus)))
        .write(
      PendingNoteOperationsCompanion(status: Value(toStatus)),
    );
  }

  Future<void> markInFlight(String noteId, Set<String> operationIds) async {
    await transaction(() async {
      for (final id in operationIds) {
        await (update(pendingNoteOperations)
              ..where((t) => t.operationId.equals(id)))
            .write(
          PendingNoteOperationsCompanion(
            status: const Value('in_flight'),
          ),
        );
      }
    });
  }

  Future<int> getProjectedOutboxOperationCount(String noteId) async {
    final count = await (select(pendingNoteOperations)
          ..where((t) => t.noteId.equals(noteId)))
        .map((row) => row.operationId)
        .get();
    return count.length;
  }

  Future<void> replacePendingOps(
    String noteId,
    List<PendingNoteOperationData> ops,
  ) async {
    await transaction(() async {
      await (delete(pendingNoteOperations)
            ..where((t) => t.noteId.equals(noteId)))
          .go();
      for (int i = 0; i < ops.length; i++) {
        final op = ops[i];
        await into(pendingNoteOperations).insert(
          PendingNoteOperationsCompanion(
            operationId: Value(op.operationId),
            noteId: Value(op.noteId),
            baseRevision: Value(op.baseRevision),
            ordinal: Value(i),
            kind: Value(op.kind),
            blockId: Value(op.blockId),
            payloadJson: Value(op.payloadJson),
            createdAt: Value(op.createdAt),
            status: const Value('pending'),
          ),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
  }

  Future<void> deletePendingOpsByStatus(String noteId, String status) async {
    await (delete(pendingNoteOperations)
          ..where((t) => t.noteId.equals(noteId) & t.status.equals(status)))
        .go();
  }

  Future<void> deleteAccepted(Set<String> operationIds) async {
    for (final id in operationIds) {
      await (delete(pendingNoteOperations)
            ..where((t) => t.operationId.equals(id)))
          .go();
    }
  }

  Future<void> runInTransaction(Future<void> Function() fn) {
    return transaction(fn);
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
