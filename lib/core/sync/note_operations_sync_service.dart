import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:supanotes/core/async/keyed_async_queue.dart';
import 'package:supanotes/core/database/daos/note_operations_dao.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/debug/note_sync_debug.dart';
import 'package:supanotes/core/sync/note_sync_persistence.dart';
import 'package:supanotes/core/sync/note_sync_reconciler.dart';
import 'package:supanotes/features/notes/editor/sync/note_operation_rebaser.dart';
import 'package:supanotes/features/notes/editor/sync/note_sync_client.dart';
import 'package:super_editor/super_editor.dart';
import 'package:uuid/uuid.dart';

class SyncResult {
  SyncResult({
    required this.acceptedCount,
    required this.acceptedOperationIds,
    required this.finalRevision,
    required this.remoteOperations,
    this.canonicalDocument,
    this.blockedReason,
  });

  final int acceptedCount;
  final List<String> acceptedOperationIds;
  final int finalRevision;
  final List<Operation> remoteOperations;
  final NoteDocumentResponse? canonicalDocument;
  final String? blockedReason;

  bool get isBlocked => blockedReason != null;

  /// Whether a pending-operation response already carried enough information
  /// for the caller to reconcile without a follow-up poll.
  bool get hasReconciliationPayload =>
      isBlocked ||
      acceptedCount > 0 ||
      canonicalDocument != null ||
      remoteOperations.isNotEmpty;

  static SyncResult empty() => SyncResult(
    acceptedCount: 0,
    acceptedOperationIds: [],
    finalRevision: 0,
    remoteOperations: [],
  );

  static SyncResult blockedByForeignSession() => SyncResult(
    acceptedCount: 0,
    acceptedOperationIds: const [],
    finalRevision: 0,
    remoteOperations: const [],
    blockedReason: 'foreign_sync_session',
  );
}

class SyncError {
  SyncError({
    required this.errorCode,
    required this.message,
    this.failedOperation,
  });

  final String errorCode;
  final String message;
  final String? failedOperation;
}

class NoteSyncTelemetrySnapshot {
  const NoteSyncTelemetrySnapshot({
    required this.noteId,
    required this.outboxOperationCount,
    required this.syncErrorCount,
    required this.hasPersistedSession,
  });

  final String noteId;
  final int outboxOperationCount;
  final int syncErrorCount;
  final bool hasPersistedSession;
}

class NoteOperationsSyncService {
  NoteOperationsSyncService({
    required NoteSyncClient syncClient,
    required NoteOperationsDao dao,
    required String clientId,
    required String actorId,
  }) : _syncClient = syncClient,
       _dao = dao,
       _clientId = clientId,
       _actorId = actorId {
    _reconciler = NoteSyncReconciler(
      rebaser: NoteOperationRebaser(localActorId: actorId),
    );
    _persistence = NoteSyncPersistence(dao);
  }

  final NoteSyncClient _syncClient;
  final NoteOperationsDao _dao;
  final String _clientId;
  final String _actorId;
  final Uuid _uuid = const Uuid();
  final _noteQueue = KeyedAsyncQueue();
  late final NoteSyncReconciler _reconciler;
  late final NoteSyncPersistence _persistence;

  String get clientId => _clientId;

  Future<T> runSerialized<T>(String noteId, Future<T> Function() fn) {
    return _noteQueue.run(noteId, fn);
  }

  Future<SyncResult> syncPending(
    String noteId, {
    Future<void> Function(SyncResult)? onReconcile,
  }) async {
    final result = await _noteQueue.run(
      noteId,
      () => _runWithSessionGate(noteId, _syncPendingWithoutSessionGate),
    );
    if (onReconcile != null) await onReconcile(result);
    return result;
  }

  Future<SyncResult> pollAndReconcile(
    String noteId, {
    Future<void> Function(SyncResult)? onReconcile,
  }) async {
    final result = await _noteQueue.run(
      noteId,
      () => _runWithSessionGate(noteId, _pollAndReconcileWithoutSessionGate),
    );
    if (onReconcile != null) await onReconcile(result);
    return result;
  }

  Future<void> enqueueOperation(String noteId, OperationRequest request) {
    return enqueueOperations(noteId, [request]);
  }

  /// Persists one editor batch as one durable outbox transaction.
  ///
  /// The per-note service queue serializes this write with sync and rebase.
  /// The service assigns base revisions from the state that is current when
  /// the batch is persisted, so a batch that waited behind a rebase cannot
  /// retain a stale revision hint from the editor.
  Future<void> enqueueOperations(
    String noteId,
    List<OperationRequest> requests, {
    String? materializedDocumentJson,
  }) {
    if (requests.isEmpty) return Future.value();
    return _noteQueue.run(
      noteId,
      () => _enqueueOperationsInner(
        noteId,
        requests,
        materializedDocumentJson: materializedDocumentJson,
      ),
    );
  }

  Future<void> _enqueueOperationsInner(
    String noteId,
    List<OperationRequest> requests, {
    String? materializedDocumentJson,
  }) async {
    await _prepareAccountScope(noteId);
    final pending = await _dao.getPendingOperations(
      noteId,
      ownerUserId: _actorId,
    );
    var ordinal = pending.isEmpty ? 0 : pending.last.ordinal + 1;
    var baseRevision = pending.isEmpty
        ? (await getConfirmedDocument(noteId))?.revision ??
              requests.first.baseRevision
        : pending.last.baseRevision + 1;
    final now = DateTime.now().toUtc();
    final operations = <PendingNoteOperationsCompanion>[];
    for (final request in requests) {
      final payloadJson = encodePayload(request.payload);
      NoteSyncDebug.log(
        'sync.enqueue',
        noteId: noteId,
        fields: {
          'operationId': request.operationId,
          'baseRevision': baseRevision,
          'ordinal': ordinal,
          'kind': request.kind,
          'blockId': request.blockId,
          'payload': payloadJson,
        },
      );
      operations.add(
        PendingNoteOperationsCompanion.insert(
          operationId: request.operationId,
          noteId: noteId,
          ownerUserId: Value(_actorId),
          baseRevision: baseRevision,
          ordinal: ordinal,
          kind: request.kind,
          blockId: Value(request.blockId),
          payloadJson: payloadJson,
          createdAt: now,
        ),
      );
      ordinal++;
      baseRevision++;
    }
    final projection = materializedDocumentJson == null
        ? null
        : _reconciler.projectMaterialized(materializedDocumentJson);
    await _persistence.persistPendingAppend(
      noteId: noteId,
      operations: operations,
      projection: projection,
    );
  }

  Future<void> storeMaterializedDocument({
    required String noteId,
    required String documentJson,
  }) {
    return _noteQueue.run(noteId, () async {
      final now = DateTime.now().toUtc();
      final projection = _reconciler.projectMaterialized(documentJson);
      await _persistence.saveLocalMaterialization(
        noteId: noteId,
        updatedAt: now,
        projection: projection,
      );
    });
  }

  Future<LocalNoteDocumentData?> getConfirmedDocument(String noteId) {
    return _dao.watchNoteDocument(noteId).first;
  }

  Future<List<PendingNoteOperationData>> getPendingOperations(String noteId) {
    return _dao.getPendingOperations(noteId, ownerUserId: _actorId);
  }

  /// Compatibility name retained for the integration sync harness.
  Future<List<PendingNoteOperationData>> loadPendingProjection(String noteId) {
    return getPendingOperations(noteId);
  }

  Future<NoteSyncTelemetrySnapshot> telemetrySnapshot(String noteId) async {
    await _prepareAccountScope(noteId);
    final outboxCount = await _dao.getProjectedOutboxOperationCount(
      noteId,
      ownerUserId: _actorId,
    );
    final errorCount = await _dao.getSyncErrorCount(
      noteId,
      ownerUserId: _actorId,
    );
    final session = await _dao.getSyncSession(noteId, ownerUserId: _actorId);
    return NoteSyncTelemetrySnapshot(
      noteId: noteId,
      outboxOperationCount: outboxCount,
      syncErrorCount: errorCount,
      hasPersistedSession: session != null,
    );
  }

  Stream<List<PendingNoteOperationData>> watchPendingOperations(String noteId) {
    return _dao.watchPendingOperations(noteId, ownerUserId: _actorId);
  }

  String generateOperationId() => _uuid.v4();

  Future<void> _prepareAccountScope(String noteId) async {
    final noteOwnerId = await _dao.getNoteOwnerId(noteId);
    if (noteOwnerId == _actorId) {
      await _dao.adoptLegacyRows(noteId, _actorId);
    }
  }

  Future<SyncResult> _runWithSessionGate(
    String noteId,
    Future<SyncResult> Function(String noteId) operation,
  ) async {
    await _prepareAccountScope(noteId);
    final activeSession = await _dao.getSyncSession(
      noteId,
      ownerUserId: _actorId,
    );
    if (activeSession != null) {
      return _resumeSyncSession(noteId, activeSession);
    }

    final foreignSession = await _dao.getAnySyncSession(noteId);
    if (foreignSession != null) {
      NoteSyncDebug.log(
        'sync.pending.blocked_foreign_session',
        noteId: noteId,
        fields: {'sessionOwner': foreignSession.ownerUserId},
      );
      return SyncResult.blockedByForeignSession();
    }
    return operation(noteId);
  }

  Future<SyncResult> _syncPendingWithoutSessionGate(String noteId) async {
    final ops = await _dao.getPendingOperations(
      noteId,
      status: 'pending',
      ownerUserId: _actorId,
    );
    if (ops.isEmpty) {
      NoteSyncDebug.log('sync.pending.empty', noteId: noteId);
      return SyncResult.empty();
    }

    final inFlightIds = ops.map((o) => o.operationId).toSet();
    final doc = await _dao.watchNoteDocument(noteId).first;
    final knownRevision = doc?.revision ?? 0;

    await _persistence.startSession(
      noteId: noteId,
      ownerUserId: _actorId,
      operationIds: inFlightIds,
      knownRevision: knownRevision,
      startedAt: DateTime.now().toUtc(),
    );

    final request = SyncRequest(
      knownRevision: knownRevision,
      operations: ops
          .map(
            (op) => OperationRequest(
              operationId: op.operationId,
              baseRevision: op.baseRevision,
              kind: op.kind,
              blockId: op.blockId,
              payload: parsePayload(op.payloadJson),
            ),
          )
          .toList(),
      clientId: _clientId,
    );
    NoteSyncDebug.log(
      'sync.request',
      noteId: noteId,
      fields: {
        'knownRevision': knownRevision,
        'operations': request.operations
            .map(
              (op) =>
                  '${op.operationId}:${op.baseRevision}:${op.kind}:${op.blockId}:${NoteSyncDebug.payloadSummary(op.payload)}',
            )
            .join('|'),
      },
    );

    final response = await _syncClient.syncOperations(noteId, request);
    NoteSyncDebug.log(
      'sync.response',
      noteId: noteId,
      fields: {
        'accepted': response.accepted.map((op) => op.operationId).join(','),
        'revision': response.finalRevision,
        'remoteOperations': response.remoteOperations.length,
        'canonical': response.canonicalDocument == null
            ? 'null'
            : NoteSyncDebug.documentSummary(response.canonicalDocument!),
      },
    );

    return _processSyncResponse(noteId, response, ops);
  }

  Future<SyncResult> _resumeSyncSession(
    String noteId,
    SyncSessionData session,
  ) async {
    final operationIds = List<String>.from(
      jsonDecode(session.operationIds) as List,
    );

    final ops = await _dao.getPendingOperations(
      noteId,
      status: 'in_flight',
      ownerUserId: _actorId,
    );
    final loadedIds = ops.map((o) => o.operationId).toSet();
    if (!_setEquals(loadedIds, operationIds.toSet())) {
      await _dao.updatePendingOpsStatus(
        noteId,
        'in_flight',
        'pending',
        ownerUserId: _actorId,
      );
      await _dao.deleteSyncSession(noteId, ownerUserId: _actorId);
      return _syncPendingWithoutSessionGate(noteId);
    }

    final request = SyncRequest(
      knownRevision: session.knownRevision,
      operations: ops
          .map(
            (op) => OperationRequest(
              operationId: op.operationId,
              baseRevision: op.baseRevision,
              kind: op.kind,
              blockId: op.blockId,
              payload: parsePayload(op.payloadJson),
            ),
          )
          .toList(),
      clientId: _clientId,
    );

    final response = await _syncClient.syncOperations(noteId, request);
    return _processSyncResponse(noteId, response, ops);
  }

  Future<SyncResult> _processSyncResponse(
    String noteId,
    SyncResponse response,
    List<PendingNoteOperationData> inFlight,
  ) async {
    NoteSyncDebug.log(
      'sync.process_response.begin',
      noteId: noteId,
      fields: {
        'expectedOperationCount': inFlight.length,
        'inFlightCount': inFlight.length,
        'remoteOperationCount': response.remoteOperations.length,
        'revision': response.finalRevision,
      },
    );
    final remaining = await _dao.getPendingOperations(
      noteId,
      status: 'pending',
      ownerUserId: _actorId,
    );
    final reconciliation = _reconciler.reconcilePending(
      noteId: noteId,
      inFlight: inFlight,
      pending: remaining,
      response: response,
    );
    NoteSyncDebug.log(
      'sync.rebase',
      noteId: noteId,
      fields: {
        'remainingPending': remaining.length,
        'rebased': reconciliation.rebasedOperations
            .map((op) => '${op.operationId}:${op.kind}:${op.blockId}')
            .join('|'),
      },
    );
    await _persistence.persistPendingReconciliation(
      noteId: noteId,
      ownerUserId: _actorId,
      reconciliation: reconciliation,
    );

    return SyncResult(
      acceptedCount: response.accepted.length,
      acceptedOperationIds: reconciliation.expectedOperationIds.toList(),
      finalRevision: response.finalRevision,
      remoteOperations: response.remoteOperations,
      canonicalDocument: NoteDocumentResponse(
        noteId: noteId,
        revision: response.finalRevision,
        document: reconciliation.response.canonicalDocument,
        serverTime: response.serverTime,
      ),
    );
  }

  Future<SyncResult> _pollAndReconcileWithoutSessionGate(String noteId) async {
    final confirmed = await _dao.watchNoteDocument(noteId).first;
    if (confirmed == null) {
      return SyncResult.empty();
    }

    final response = await _syncClient.getOperationsSince(
      noteId,
      confirmed.revision,
    );
    NoteSyncDebug.log(
      'sync.poll.response',
      noteId: noteId,
      fields: {
        'fromRevision': confirmed.revision,
        'operations': response.operations.length,
        'revision': response.revision,
      },
    );

    if (response.operations.isEmpty) {
      return SyncResult.empty();
    }

    final pending = await _dao.getPendingOperations(
      noteId,
      status: 'pending',
      ownerUserId: _actorId,
    );
    final reconciliation = _reconciler.reconcilePoll(
      noteId: noteId,
      fromRevision: confirmed.revision,
      response: response,
      pending: pending,
    );
    final now = DateTime.now().toUtc();
    await _persistence.persistPollReconciliation(
      noteId: noteId,
      ownerUserId: _actorId,
      reconciliation: reconciliation,
      updatedAt: now,
    );

    return SyncResult(
      acceptedCount: 0,
      acceptedOperationIds: [],
      finalRevision: reconciliation.response.revision,
      remoteOperations: reconciliation.response.operations,
      canonicalDocument: NoteDocumentResponse(
        noteId: noteId,
        revision: reconciliation.response.revision,
        document: reconciliation.response.document,
        serverTime: now,
      ),
    );
  }

  static bool _setEquals(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    for (final e in a) {
      if (!b.contains(e)) return false;
    }
    return true;
  }

  static Map<String, dynamic> parsePayload(String json) {
    return Map<String, dynamic>.from(jsonDecode(json) as Map);
  }

  static String encodePayload(Map<String, dynamic> payload) {
    return jsonEncode(_toJsonValue(payload));
  }

  static dynamic _toJsonValue(dynamic value) {
    if (value is Attribution) return value.id;
    if (value is DateTime) return value.toUtc().toIso8601String();
    if (value is Map) {
      return value.map(
        (key, entry) => MapEntry(key.toString(), _toJsonValue(entry)),
      );
    }
    if (value is Iterable) return value.map(_toJsonValue).toList();
    return value;
  }
}
