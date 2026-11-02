import 'dart:convert';

import 'package:drift/drift.dart';

import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/database/note_lifecycle_policy.dart';
import 'package:supanotes/core/database/tables/local_note_documents.dart';
import 'package:supanotes/core/database/tables/note_sync_errors.dart';
import 'package:supanotes/core/database/tables/note_tasks.dart';
import 'package:supanotes/core/database/tables/notes.dart';
import 'package:supanotes/core/database/tables/pending_note_operations.dart';
import 'package:supanotes/core/database/tables/sync_sessions.dart';
import 'package:supanotes/core/database/tables/user_note_preferences.dart';
import 'package:supanotes/features/tasks/domain/note_task_reader.dart';

part 'note_operations_dao.g.dart';

@DriftAccessor(
  tables: [
    LocalNoteDocuments,
    PendingNoteOperations,
    NoteSyncErrors,
    Notes,
    SyncSessions,
    NoteTasks,
    UserNotePreferences,
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

  /// Single-shot read for callers that need the current row, not updates.
  ///
  /// `watchNoteDocument(...).first` opens a query stream that is cancelled
  /// immediately afterwards, which costs a stream lifecycle per read.
  Future<LocalNoteDocumentData?> getNoteDocument(String noteId) {
    return (select(
      localNoteDocuments,
    )..where((t) => t.noteId.equals(noteId))).getSingleOrNull();
  }

  Future<void> upsertNoteDocument(LocalNoteDocumentsCompanion doc) async {
    await transaction(() => upsertNoteDocumentInTransaction(doc));
  }

  Future<void> upsertNoteDocumentInTransaction(
    LocalNoteDocumentsCompanion doc,
  ) async {
    await into(
      localNoteDocuments,
    ).insert(doc, onConflict: DoUpdate((_) => doc));
    if (doc.noteId.present && doc.materializedDocumentJson.present) {
      await replaceNoteTasksInTransaction(
        doc.noteId.value,
        doc.materializedDocumentJson.value,
      );
    }
    if (doc.noteId.present) {
      await attachedDatabase.noteLifecycleDao.markMaterialized(
        doc.noteId.value,
      );
    }
  }

  Future<void> saveMaterializedDocument({
    required String noteId,
    required String documentJson,
    required String content,
    required String? excerpt,
    required DateTime updatedAt,
  }) async {
    await transaction(
      () => saveMaterializedDocumentInTransaction(
        noteId: noteId,
        documentJson: documentJson,
        content: content,
        excerpt: excerpt,
        updatedAt: updatedAt,
      ),
    );
  }

  Future<void> saveMaterializedDocumentInTransaction({
    required String noteId,
    required String documentJson,
    required String content,
    required String? excerpt,
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
      );
    }
    await attachedDatabase.notesDao.updateNoteProjection(
      id: noteId,
      content: content,
      excerpt: excerpt,
      materialized: content.isNotEmpty,
      updatedAt: updatedAt,
    );
    await replaceNoteTasksInTransaction(noteId, documentJson);
  }

  Future<void> deleteNoteDocument(String noteId) async {
    await (delete(
      localNoteDocuments,
    )..where((t) => t.noteId.equals(noteId))).go();
    await deleteNoteTasks(noteId);
  }

  /// Rewrites the `note_tasks` projection of [noteId] from its materialized
  /// document, touching the table only when the task blocks changed.
  ///
  /// Typing in a paragraph therefore leaves the projection (and every query
  /// that watches it) untouched; only edits to task blocks rewrite one note's
  /// rows. Must run inside the transaction that stores the document.
  Future<void> replaceNoteTasksInTransaction(
    String noteId,
    String? materializedDocumentJson,
  ) async {
    final next = projectNoteTaskRows(noteId, materializedDocumentJson);
    final current =
        await (select(noteTasks)
              ..where((t) => t.noteId.equals(noteId))
              ..orderBy([(t) => OrderingTerm(expression: t.position)]))
            .get();
    if (_sameRows(current, next)) return;
    await deleteNoteTasks(noteId);
    if (next.isEmpty) return;
    await batch((batch) => batch.insertAll(noteTasks, next));
  }

  Future<void> deleteNoteTasks(String noteId) async {
    await (delete(noteTasks)..where((t) => t.noteId.equals(noteId))).go();
  }

  static bool _sameRows(List<NoteTaskRow> a, List<NoteTaskRow> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Streams the projected tasks of every note visible to [userId].
  ///
  /// Visibility mirrors the notes catalog: owned or currently shared,
  /// materialized, not archived and not deleted. Only the first line of the
  /// note text is read (for the note title), and rows are ordered by stable
  /// identity, so saves that do not touch tasks or the title produce an
  /// identical result that consumers can drop with `distinct`.
  ///
  /// Pass `withNoteTitle: false` when the note title is not shown (reminders),
  /// so editing a note's first line does not wake that consumer either.
  Stream<List<VisibleNoteTaskRow>> watchVisibleNoteTasks(
    String userId, {
    bool withNoteTitle = true,
  }) {
    return customSelect(
      'SELECT t.note_id, t.block_id, t.position, t.title, t.metadata_json, '
      't.invalid_reason, n.created_at, '
      '${withNoteTitle ? withNoteTitleSql : "''"} AS first_line '
      'FROM note_tasks t '
      'JOIN notes n ON n.id = t.note_id '
      'LEFT JOIN user_note_preferences unp '
      'ON unp.note_id = n.id AND unp.user_id = ? '
      'WHERE COALESCE(unp.archived, 0) = 0 AND n.deleted_at IS NULL '
      "AND n.lifecycle_state <> '$emptyDraftLifecycleState' "
      'AND (n.user_id = ? OR '
      "(n.permission IN ('view', 'edit') AND unp.note_id IS NOT NULL)) "
      'ORDER BY t.note_id, t.position',
      variables: [Variable.withString(userId), Variable.withString(userId)],
      readsFrom: {noteTasks, notes, userNotePreferences},
    ).watch().map(
      (rows) => [
        for (final row in rows)
          (
            noteId: row.read<String>('note_id'),
            blockId: row.read<String>('block_id'),
            position: row.read<int>('position'),
            title: row.read<String>('title'),
            metadataJson: row.read<String>('metadata_json'),
            invalidReason: row.read<String?>('invalid_reason'),
            noteCreatedAt: row.read<DateTime>('created_at'),
            noteFirstLine: row.read<String>('first_line'),
          ),
      ],
    );
  }

  /// Whether [noteId] was created on this device and has not reached the
  /// server yet.
  ///
  /// Such a note exists only locally until its first sync is accepted, and
  /// asking the server about it is answered with 403/404, which the editor
  /// session must not mistake for a revoked permission. Notes known only
  /// through a server document (no local note row) are not local-only.
  Future<bool> isNoteLocalOnly(String noteId) async {
    final row = await (select(
      notes,
    )..where((t) => t.id.equals(noteId))).getSingleOrNull();
    return row != null && !row.hasRemoteCopy;
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
    return transaction(() => insertPendingOperationsInTransaction([op]));
  }

  Future<void> insertPendingOperationsInTransaction(
    List<PendingNoteOperationsCompanion> operations,
  ) async {
    if (operations.isEmpty) return;
    final inputIds = <String>{};
    final newOperations = <PendingNoteOperationsCompanion>[];
    for (final operation in operations) {
      if (!operation.operationId.present || !operation.noteId.present) {
        throw ArgumentError('Pending operation identity is required');
      }
      final operationId = operation.operationId.value;
      if (!inputIds.add(operationId)) {
        throw StateError(
          'Duplicate operationId in pending batch: $operationId',
        );
      }
    }

    final existingOperations = await (select(
      pendingNoteOperations,
    )..where((row) => row.operationId.isIn(inputIds))).get();
    final existingById = {
      for (final operation in existingOperations)
        operation.operationId: operation,
    };
    for (final operation in operations) {
      final operationId = operation.operationId.value;
      final existing = existingById[operationId];
      if (existing != null) {
        if (!_sameOperation(existing, operation)) {
          throw StateError(
            'Operation ID $operationId was reused with a different payload',
          );
        }
      } else {
        newOperations.add(operation);
      }
    }
    if (newOperations.isNotEmpty) {
      await batch((batch) {
        batch.insertAll(pendingNoteOperations, newOperations);
      });
      await attachedDatabase.noteLifecycleDao.markMaterialized(
        newOperations.first.noteId.value,
      );
    }
  }

  bool _sameOperation(
    PendingNoteOperationData existing,
    PendingNoteOperationsCompanion incoming,
  ) {
    return existing.noteId == incoming.noteId.value &&
        existing.ownerUserId == incoming.ownerUserId.value &&
        existing.baseRevision == incoming.baseRevision.value &&
        existing.ordinal == incoming.ordinal.value &&
        existing.kind == incoming.kind.value &&
        existing.blockId == incoming.blockId.value &&
        existing.payloadJson == incoming.payloadJson.value;
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

  /// Returns the highest-ordinal pending operation for [noteId], or `null`.
  ///
  /// Appending a batch only needs the tail of the outbox; reading every
  /// pending row (with payloads) made each keystroke batch O(outbox size)
  /// while offline.
  Future<PendingNoteOperationData?> getLastPendingOperation(
    String noteId, {
    String? ownerUserId,
  }) {
    final query = select(pendingNoteOperations)
      ..where((t) => t.noteId.equals(noteId));
    if (ownerUserId != null) {
      query.where((t) => t.ownerUserId.equals(ownerUserId));
    }
    query
      ..orderBy([
        (t) => OrderingTerm(expression: t.ordinal, mode: OrderingMode.desc),
      ])
      ..limit(1);
    return query.getSingleOrNull();
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

  Future<void> markInFlightInTransaction(
    String noteId,
    Set<String> operationIds, {
    String? ownerUserId,
  }) async {
    if (operationIds.isEmpty) return;
    final query = update(
      pendingNoteOperations,
    )..where((t) => t.noteId.equals(noteId) & t.operationId.isIn(operationIds));
    if (ownerUserId != null) {
      query.where((t) => t.ownerUserId.equals(ownerUserId));
    }
    await query.write(
      const PendingNoteOperationsCompanion(status: Value('in_flight')),
    );
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

  Future<void> replacePendingOpsInTransaction(
    String noteId,
    List<PendingNoteOperationData> ops, {
    String? ownerUserId,
  }) async {
    final deleteQuery = delete(pendingNoteOperations)
      ..where((t) => t.noteId.equals(noteId));
    if (ownerUserId != null) {
      deleteQuery.where((t) => t.ownerUserId.equals(ownerUserId));
    }
    await deleteQuery.go();
    final companions = [
      for (var i = 0; i < ops.length; i++)
        PendingNoteOperationsCompanion(
          operationId: Value(ops[i].operationId),
          noteId: Value(ops[i].noteId),
          ownerUserId: Value(ownerUserId ?? ops[i].ownerUserId),
          baseRevision: Value(ops[i].baseRevision),
          ordinal: Value(i),
          kind: Value(ops[i].kind),
          blockId: Value(ops[i].blockId),
          payloadJson: Value(ops[i].payloadJson),
          createdAt: Value(ops[i].createdAt),
          status: const Value('pending'),
        ),
    ];
    await insertPendingOperationsInTransaction(companions);
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

  Future<void> deleteAcceptedInTransaction(
    Set<String> operationIds, {
    String? noteId,
    String? ownerUserId,
  }) async {
    if (operationIds.isEmpty) return;
    final query = delete(pendingNoteOperations)
      ..where((t) => t.operationId.isIn(operationIds));
    if (noteId != null) query.where((t) => t.noteId.equals(noteId));
    if (ownerUserId != null) {
      query.where((t) => t.ownerUserId.equals(ownerUserId));
    }
    await query.go();
  }

  Future<void> runInTransaction(Future<void> Function() fn) {
    return transaction(fn);
  }

  Future<void> deleteSyncSessionInTransaction(
    String noteId, {
    String? ownerUserId,
  }) async {
    final query = delete(syncSessions)..where((t) => t.noteId.equals(noteId));
    if (ownerUserId != null) {
      query.where((t) => t.ownerUserId.equals(ownerUserId));
    }
    await query.go();
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

/// SQL expression for the first line of a note's plain text (its title).
const withNoteTitleSql =
    "substr(ltrim(n.content, char(10)), 1, "
    "instr(ltrim(n.content, char(10)) || char(10), char(10)) - 1)";

/// One projected task joined with the note fields its readers need.
typedef VisibleNoteTaskRow = ({
  String noteId,
  String blockId,
  int position,
  String title,
  String metadataJson,
  String? invalidReason,
  DateTime noteCreatedAt,
  String noteFirstLine,
});

/// Builds the projection rows for one materialized document.
///
/// A document that cannot be read becomes a single marker row carrying the
/// error, so the failure stays visible to readers instead of hiding the note.
List<NoteTaskRow> projectNoteTaskRows(
  String noteId,
  String? materializedDocumentJson,
) {
  if (materializedDocumentJson == null) return const [];
  try {
    final blocks = extractNoteTaskBlocks(materializedDocumentJson);
    return [
      for (var i = 0; i < blocks.length; i++)
        NoteTaskRow(
          noteId: noteId,
          blockId: blocks[i].blockId,
          position: i,
          title: blocks[i].title,
          metadataJson: jsonEncode(blocks[i].metadata),
        ),
    ];
  } on Object catch (error) {
    return [
      NoteTaskRow(
        noteId: noteId,
        blockId: '',
        position: 0,
        title: '',
        metadataJson: '{}',
        invalidReason: error.toString(),
      ),
    ];
  }
}
