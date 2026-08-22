import 'dart:convert';

import 'package:drift/drift.dart';

import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/database/note_lifecycle_policy.dart';
import 'package:supanotes/core/database/tables/local_note_documents.dart';
import 'package:supanotes/core/database/tables/note_sync_errors.dart';
import 'package:supanotes/core/database/tables/notes.dart';
import 'package:supanotes/core/database/tables/pending_note_operations.dart';
import 'package:supanotes/core/database/tables/sync_sessions.dart';
import 'package:supanotes/features/notes/editor/document/note_document_codec.dart';

part 'note_operations_dao.g.dart';

@DriftAccessor(
  tables: [
    LocalNoteDocuments,
    PendingNoteOperations,
    NoteSyncErrors,
    Notes,
    SyncSessions,
  ],
)
class NoteOperationsDao extends DatabaseAccessor<AppDatabase>
    with _$NoteOperationsDaoMixin {
  NoteOperationsDao(super.db);

  Stream<LocalNoteDocumentData?> watchNoteDocument(String noteId) {
    return (select(
      localNoteDocuments,
    )..where((t) => t.noteId.equals(noteId))).watchSingleOrNull();
  }

  Stream<List<LocalNoteDocumentData>> watchMaterializedDocuments() {
    final query =
        select(localNoteDocuments).join([
          innerJoin(notes, notes.id.equalsExp(localNoteDocuments.noteId)),
        ])..where(
          localNoteDocuments.materializedDocumentJson.isNotNull() &
              notes.deletedAt.isNull(),
        );
    return query.watch().map(
      (rows) => rows.map((row) => row.readTable(localNoteDocuments)).toList(),
    );
  }

  Future<void> upsertNoteDocument(LocalNoteDocumentsCompanion doc) async {
    await transaction(() async {
      await into(
        localNoteDocuments,
      ).insert(doc, onConflict: DoUpdate((_) => doc));
      if (doc.noteId.present) {
        await attachedDatabase.noteLifecycleDao.markMaterialized(
          doc.noteId.value,
        );
      }
    });
  }

  Future<void> updateMaterializedDocument({
    required String noteId,
    required String documentJson,
    required DateTime updatedAt,
  }) async {
    final changed =
        await (update(
          localNoteDocuments,
        )..where((t) => t.noteId.equals(noteId))).write(
          LocalNoteDocumentsCompanion(
            materializedDocumentJson: Value(documentJson),
            materializedUpdatedAt: Value(updatedAt),
          ),
        );
    if (changed == 0) {
      await into(localNoteDocuments).insert(
        LocalNoteDocumentsCompanion.insert(
          noteId: noteId,
          revision: 0,
          documentJson: '{"schemaVersion":1,"blocks":[]}',
          updatedAt: updatedAt,
          materializedDocumentJson: Value(documentJson),
          materializedUpdatedAt: Value(updatedAt),
        ),
        mode: InsertMode.insertOrReplace,
      );
    }
    await _projectToNotesTable(noteId, documentJson, updatedAt: updatedAt);
  }

  Future<void> _projectToNotesTable(
    String noteId,
    String documentJson, {
    DateTime? updatedAt,
  }) async {
    try {
      final decoded = jsonDecode(documentJson);
      if (decoded is Map && decoded['blocks'] is List) {
        final projection = const NoteDocumentCodec().projectContent(
          decoded['blocks'] as List<dynamic>,
        );
        await attachedDatabase.notesDao.updateNoteProjection(
          id: noteId,
          content: projection.content,
          excerpt: projection.excerpt,
          materialized: projection.content.isNotEmpty,
          updatedAt: updatedAt,
        );
      }
    } catch (_) {
      // Best-effort projection
    }
  }

  Future<void> deleteNoteDocument(String noteId) async {
    await (delete(
      localNoteDocuments,
    )..where((t) => t.noteId.equals(noteId))).go();
  }

  Future<void> markNoteHasRemoteCopy(String noteId) async {
    await (update(notes)..where((note) => note.id.equals(noteId))).write(
      const NotesCompanion(
        hasRemoteCopy: Value(true),
        lifecycleState: Value(materializedLifecycleState),
      ),
    );
  }

  Future<void> insertPendingOperation(PendingNoteOperationsCompanion op) {
    return transaction(() => _insertPendingOperationAndMarkMaterialized(op));
  }

  Future<void> _insertPendingOperationAndMarkMaterialized(
    PendingNoteOperationsCompanion op,
  ) async {
    await into(
      pendingNoteOperations,
    ).insert(op, mode: InsertMode.insertOrReplace);
    if (op.noteId.present) {
      await attachedDatabase.noteLifecycleDao.markMaterialized(op.noteId.value);
    }
  }

  Stream<List<PendingNoteOperationData>> watchPendingOperations(
    String noteId, {
    String? ownerUserId,
  }) {
    final query = select(pendingNoteOperations)
      ..where((t) => t.noteId.equals(noteId));
    if (ownerUserId != null) {
      query.where((t) => t.ownerUserId.equals(ownerUserId));
    }
    query.orderBy([(t) => OrderingTerm(expression: t.ordinal)]);
    return query.watch();
  }

  Future<List<PendingNoteOperationData>> getPendingOperations(
    String noteId, {
    String? status,
    String? ownerUserId,
  }) async {
    final query = select(pendingNoteOperations)
      ..where((t) => t.noteId.equals(noteId));
    if (status != null) {
      query.where((t) => t.status.equals(status));
    }
    if (ownerUserId != null) {
      query.where((t) => t.ownerUserId.equals(ownerUserId));
    }
    query.orderBy([(t) => OrderingTerm(expression: t.ordinal)]);
    return query.get();
  }

  Future<String?> getNoteOwnerId(String noteId) async {
    final note = await (select(
      notes,
    )..where((t) => t.id.equals(noteId))).getSingleOrNull();
    return note?.userId;
  }

  /// Assigns legacy unscoped rows only when the local note proves ownership.
  ///
  /// Shared-note rows and rows without a local ownership record remain
  /// unscoped and are hidden from account-scoped sync.
  Future<void> adoptLegacyRows(String noteId, String ownerUserId) async {
    await transaction(() async {
      await (update(
        pendingNoteOperations,
      )..where((t) => t.noteId.equals(noteId) & t.ownerUserId.isNull())).write(
        PendingNoteOperationsCompanion(ownerUserId: Value(ownerUserId)),
      );
      await (update(syncSessions)
            ..where((t) => t.noteId.equals(noteId) & t.ownerUserId.isNull()))
          .write(SyncSessionsCompanion(ownerUserId: Value(ownerUserId)));
      await (update(noteSyncErrors)
            ..where((t) => t.noteId.equals(noteId) & t.ownerUserId.isNull()))
          .write(NoteSyncErrorsCompanion(ownerUserId: Value(ownerUserId)));
    });
  }

  Future<void> deletePendingOperation(String operationId) async {
    await (delete(
      pendingNoteOperations,
    )..where((t) => t.operationId.equals(operationId))).go();
  }

  Future<void> deletePendingOperationsForNote(String noteId) async {
    await (delete(
      pendingNoteOperations,
    )..where((t) => t.noteId.equals(noteId))).go();
  }

  Future<void> deleteStalePendingOps(String noteId, int minBaseRevision) async {
    await (delete(pendingNoteOperations)..where(
          (t) =>
              t.noteId.equals(noteId) &
              t.baseRevision.isSmallerThanValue(minBaseRevision),
        ))
        .go();
  }

  Future<void> incrementAttempt(String operationId) async {
    final op = await (select(
      pendingNoteOperations,
    )..where((t) => t.operationId.equals(operationId))).getSingleOrNull();
    if (op == null) return;
    await (update(
      pendingNoteOperations,
    )..where((t) => t.operationId.equals(operationId))).write(
      PendingNoteOperationsCompanion(
        attemptCount: Value(op.attemptCount + 1),
        lastAttemptAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  // ---- Sync session CRUD ----

  Future<SyncSessionData?> getSyncSession(
    String noteId, {
    String? ownerUserId,
  }) {
    final query = select(syncSessions)..where((t) => t.noteId.equals(noteId));
    if (ownerUserId != null) {
      query.where((t) => t.ownerUserId.equals(ownerUserId));
    }
    return query.getSingleOrNull();
  }

  Future<SyncSessionData?> getAnySyncSession(String noteId) {
    return (select(
      syncSessions,
    )..where((t) => t.noteId.equals(noteId))).getSingleOrNull();
  }

  Future<void> upsertSyncSession(SyncSessionsCompanion session) {
    return into(
      syncSessions,
    ).insert(session, onConflict: DoUpdate((_) => session));
  }

  Future<void> deleteSyncSession(String noteId, {String? ownerUserId}) async {
    final query = delete(syncSessions)..where((t) => t.noteId.equals(noteId));
    if (ownerUserId != null) {
      query.where((t) => t.ownerUserId.equals(ownerUserId));
    }
    await query.go();
  }

  // ---- Outbox status ----

  Future<void> updatePendingOpsStatus(
    String noteId,
    String fromStatus,
    String toStatus, {
    String? ownerUserId,
  }) async {
    final query = update(pendingNoteOperations)
      ..where((t) => t.noteId.equals(noteId) & t.status.equals(fromStatus));
    if (ownerUserId != null) {
      query.where((t) => t.ownerUserId.equals(ownerUserId));
    }
    await query.write(PendingNoteOperationsCompanion(status: Value(toStatus)));
  }

  Future<void> markInFlight(String noteId, Set<String> operationIds) async {
    await transaction(() async {
      for (final id in operationIds) {
        await (update(
          pendingNoteOperations,
        )..where((t) => t.operationId.equals(id))).write(
          const PendingNoteOperationsCompanion(status: Value('in_flight')),
        );
      }
    });
  }

  Future<int> getProjectedOutboxOperationCount(
    String noteId, {
    String? ownerUserId,
  }) async {
    final query = select(pendingNoteOperations)
      ..where((t) => t.noteId.equals(noteId));
    if (ownerUserId != null) {
      query.where((t) => t.ownerUserId.equals(ownerUserId));
    }
    final count = await query.map((row) => row.operationId).get();
    return count.length;
  }

  Future<int> getSyncErrorCount(String noteId, {String? ownerUserId}) async {
    final query = select(noteSyncErrors)..where((t) => t.noteId.equals(noteId));
    if (ownerUserId != null) {
      query.where((t) => t.ownerUserId.equals(ownerUserId));
    }
    final count = await query.map((row) => row.operationId).get();
    return count.length;
  }

  Future<void> replacePendingOps(
    String noteId,
    List<PendingNoteOperationData> ops, {
    String? ownerUserId,
  }) async {
    await transaction(() async {
      final deleteQuery = delete(pendingNoteOperations)
        ..where((t) => t.noteId.equals(noteId));
      if (ownerUserId != null) {
        deleteQuery.where((t) => t.ownerUserId.equals(ownerUserId));
      }
      await deleteQuery.go();
      for (var i = 0; i < ops.length; i++) {
        final op = ops[i];
        await into(pendingNoteOperations).insert(
          PendingNoteOperationsCompanion(
            operationId: Value(op.operationId),
            noteId: Value(op.noteId),
            ownerUserId: Value(ownerUserId ?? op.ownerUserId),
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
      if (ops.isNotEmpty) {
        await attachedDatabase.noteLifecycleDao.markMaterialized(noteId);
      }
    });
  }

  Future<void> deletePendingOpsByStatus(
    String noteId,
    String status, {
    String? ownerUserId,
  }) async {
    final query = delete(pendingNoteOperations)
      ..where((t) => t.noteId.equals(noteId) & t.status.equals(status));
    if (ownerUserId != null) {
      query.where((t) => t.ownerUserId.equals(ownerUserId));
    }
    await query.go();
  }

  Future<void> deleteAccepted(Set<String> operationIds) async {
    for (final id in operationIds) {
      await (delete(
        pendingNoteOperations,
      )..where((t) => t.operationId.equals(id))).go();
    }
  }

  Future<void> runInTransaction(Future<void> Function() fn) {
    return transaction(fn);
  }

  Future<void> insertSyncError(NoteSyncErrorsCompanion error) {
    return into(noteSyncErrors).insert(error, mode: InsertMode.insertOrReplace);
  }

  Stream<List<NoteSyncErrorData>> watchSyncErrors(
    String noteId, {
    String? ownerUserId,
  }) {
    final query = select(noteSyncErrors)..where((t) => t.noteId.equals(noteId));
    if (ownerUserId != null) {
      query.where((t) => t.ownerUserId.equals(ownerUserId));
    }
    query.orderBy([(t) => OrderingTerm(expression: t.createdAt)]);
    return query.watch();
  }

  Future<void> deleteSyncError(String operationId) async {
    await (delete(
      noteSyncErrors,
    )..where((t) => t.operationId.equals(operationId))).go();
  }
}
