import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:supanotes/core/database/daos/note_operations_dao.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/sync/note_document_projection.dart';
import 'package:supanotes/core/sync/note_sync_reconciler.dart';

/// Owns the local transaction for a previously validated reconciliation.
/// Network, protocol, rebase and projection code is intentionally absent here.
final class NoteSyncPersistence {
  const NoteSyncPersistence(this._dao);

  final NoteOperationsDao _dao;

  Future<void> startSession({
    required String noteId,
    required String ownerUserId,
    required Set<String> operationIds,
    required int knownRevision,
    required DateTime startedAt,
  }) {
    return _dao.runInTransaction(() async {
      await _dao.markInFlightInTransaction(
        noteId,
        operationIds,
        ownerUserId: ownerUserId,
      );
      await _dao.upsertSyncSession(
        SyncSessionsCompanion.insert(
          noteId: noteId,
          ownerUserId: Value(ownerUserId),
          knownRevision: knownRevision,
          operationIds: jsonEncode(operationIds.toList(growable: false)),
          startedAt: startedAt.toUtc().toIso8601String(),
        ),
      );
    });
  }

  Future<void> saveLocalMaterialization({
    required String noteId,
    required DateTime updatedAt,
    required NoteDocumentProjection projection,
  }) {
    return _dao.runInTransaction(
      () => _dao.saveMaterializedDocumentInTransaction(
        noteId: noteId,
        documentJson: projection.materializedJson,
        content: projection.content,
        excerpt: projection.excerpt,
        updatedAt: updatedAt,
      ),
    );
  }

  Future<void> persistPendingAppend({
    required String noteId,
    required List<PendingNoteOperationsCompanion> operations,
    NoteDocumentProjection? projection,
  }) {
    return _dao.runInTransaction(() async {
      final updatedAt = DateTime.now().toUtc();
      await _dao.insertPendingOperationsInTransaction(operations);
      if (projection != null) {
        await _dao.saveMaterializedDocumentInTransaction(
          noteId: noteId,
          documentJson: projection.materializedJson,
          content: projection.content,
          excerpt: projection.excerpt,
          updatedAt: updatedAt,
        );
      }
    });
  }

  Future<void> persistPendingReconciliation({
    required String noteId,
    required String ownerUserId,
    required NoteSyncReconciliation reconciliation,
  }) {
    final response = reconciliation.response.response;
    return _dao.runInTransaction(() async {
      await _dao.deleteAcceptedInTransaction(
        reconciliation.expectedOperationIds,
        noteId: noteId,
        ownerUserId: ownerUserId,
      );
      await _dao.upsertNoteDocumentInTransaction(
        LocalNoteDocumentsCompanion.insert(
          noteId: noteId,
          revision: response.finalRevision,
          documentJson: reconciliation.projection.canonicalJson,
          updatedAt: response.serverTime,
        ),
      );
      await _dao.saveMaterializedDocumentInTransaction(
        noteId: noteId,
        documentJson: reconciliation.projection.materializedJson,
        content: reconciliation.projection.content,
        excerpt: reconciliation.projection.excerpt,
        updatedAt: response.serverTime,
      );
      await _dao.markNoteHasRemoteCopy(noteId);
      await _dao.replacePendingOpsInTransaction(
        noteId,
        reconciliation.rebasedOperations,
        ownerUserId: ownerUserId,
      );
      await _dao.deleteSyncSessionInTransaction(
        noteId,
        ownerUserId: ownerUserId,
      );
    });
  }

  Future<void> persistPollReconciliation({
    required String noteId,
    required String ownerUserId,
    required NotePollReconciliation reconciliation,
    required DateTime updatedAt,
  }) {
    return _dao.runInTransaction(() async {
      await _dao.upsertNoteDocumentInTransaction(
        LocalNoteDocumentsCompanion.insert(
          noteId: noteId,
          revision: reconciliation.response.revision,
          documentJson: reconciliation.projection.canonicalJson,
          updatedAt: updatedAt,
        ),
      );
      await _dao.saveMaterializedDocumentInTransaction(
        noteId: noteId,
        documentJson: reconciliation.projection.materializedJson,
        content: reconciliation.projection.content,
        excerpt: reconciliation.projection.excerpt,
        updatedAt: updatedAt,
      );
      await _dao.replacePendingOpsInTransaction(
        noteId,
        reconciliation.rebasedOperations,
        ownerUserId: ownerUserId,
      );
    });
  }
}
