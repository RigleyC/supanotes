import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:supanotes/core/database/daos/note_operations_dao.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/features/notes/data/note_operations_api.dart';
import 'package:supanotes/features/notes/domain/note_operation_rebaser.dart';

class SyncResult {
  final int acceptedCount;
  final List<String> acceptedOperationIds;
  final int finalRevision;
  final List<Operation> remoteOperations;
  final NoteDocumentResponse? canonicalDocument;

  SyncResult({
    required this.acceptedCount,
    required this.acceptedOperationIds,
    required this.finalRevision,
    required this.remoteOperations,
    this.canonicalDocument,
  });

  static SyncResult empty() => SyncResult(
        acceptedCount: 0,
        acceptedOperationIds: [],
        finalRevision: 0,
        remoteOperations: [],
      );
}

class SyncError {
  final String errorCode;
  final String message;
  final String? failedOperation;

  SyncError({
    required this.errorCode,
    required this.message,
    this.failedOperation,
  });
}

class _NoteSyncQueue {
  final Map<String, Future<void>> _tails = {};

  Future<T> run<T>(String noteId, Future<T> Function() fn) {
    final previous = _tails[noteId] ?? Future<void>.value();
    final result = previous.then((_) => fn());
    final tail = result.then<void>((_) {}, onError: (_, _) {});
    _tails[noteId] = tail;
    return result.whenComplete(() {
      if (identical(_tails[noteId], tail)) _tails.remove(noteId);
    });
  }
}

class NoteOperationsSyncService {
  final NoteOperationsApiClient _api;
  final NoteOperationsDao _dao;
  final String _clientId;
  final Uuid _uuid = const Uuid();
  final _NoteSyncQueue _syncQueue = _NoteSyncQueue();
  late final NoteOperationRebaser _rebaser;

  NoteOperationsSyncService({
    required NoteOperationsApiClient api,
    required NoteOperationsDao dao,
    required String clientId,
    required String actorId,
  })  : _api = api,
        _dao = dao,
        _clientId = clientId {
    _rebaser = NoteOperationRebaser(localActorId: actorId);
  }

  String get clientId => _clientId;

  Future<T> runSerialized<T>(String noteId, Future<T> Function() fn) {
    return _syncQueue.run(noteId, fn);
  }

  // ---- Public API ----

  Future<SyncResult> syncPending(String noteId) {
    return _syncQueue.run(noteId, () => _syncPendingInner(noteId));
  }

  Future<SyncResult> pollAndReconcile(String noteId) {
    return _syncQueue.run(noteId, () => _pollAndReconcileInner(noteId));
  }

  Future<void> enqueueOperation(
    String noteId,
    OperationRequest request,
  ) {
    return _enqueueOperationInner(noteId, request);
  }

  Future<void> _enqueueOperationInner(
    String noteId,
    OperationRequest request,
  ) async {
    final pending = await _dao.getPendingOperations(noteId);
    final ordinal = pending.isEmpty ? 0 : pending.last.ordinal + 1;

    await _dao.insertPendingOperation(
      PendingNoteOperationsCompanion.insert(
        operationId: request.operationId,
        noteId: noteId,
        baseRevision: request.baseRevision,
        ordinal: ordinal,
        kind: request.kind,
        blockId: Value(request.blockId),
        payloadJson: encodePayload(request.payload),
        createdAt: DateTime.now().toUtc(),
      ),
    );
  }

  Future<void> storeDocument(String noteId, NoteDocumentResponse doc) async {
    await _dao.upsertNoteDocument(
      LocalNoteDocumentsCompanion.insert(
        noteId: doc.noteId,
        revision: doc.revision,
        documentJson: encodeDocument(doc.document),
        updatedAt: doc.serverTime,
      ),
    );
  }

  Future<NoteDocumentResponse?> fetchDocument(String noteId) async {
    try {
      return await _api.getDocument(noteId);
    } on NoteOperationsException catch (e) {
      dev.log(
        '[NoteOperationsSyncService] fetchDocument failed for note=$noteId: $e',
        name: 'NoteOperationsSync',
      );
      return null;
    }
  }

  Future<LocalNoteDocumentData?> getConfirmedDocument(String noteId) {
    return _dao.watchNoteDocument(noteId).first;
  }

  Future<List<PendingNoteOperationData>> getPendingOperations(
    String noteId,
  ) {
    return _dao.getPendingOperations(noteId);
  }

  Future<List<PendingNoteOperationData>> loadPendingProjection(String noteId) {
    return _dao.getPendingOperations(noteId, status: 'pending');
  }

  Future<int> getProjectedOutboxOperationCount(String noteId) {
    return _dao.getProjectedOutboxOperationCount(noteId);
  }

  Stream<List<PendingNoteOperationData>> watchPendingOperations(
    String noteId,
  ) {
    return _dao.watchPendingOperations(noteId);
  }

  String generateOperationId() => _uuid.v4();

  // ---- Internal ----

  Future<SyncResult> _syncPendingInner(String noteId) async {
    final activeSession = await _dao.getSyncSession(noteId);
    if (activeSession != null) {
      return _resumeSyncSession(noteId, activeSession);
    }

    final ops = await _dao.getPendingOperations(noteId, status: 'pending');
    if (ops.isEmpty) {
      return SyncResult.empty();
    }

    final inFlightIds = ops.map((o) => o.operationId).toSet();
    final doc = await _dao.watchNoteDocument(noteId).first;
    final knownRevision = doc?.revision ?? 0;

    await _dao.runInTransaction(() async {
      await _dao.markInFlight(noteId, inFlightIds);
      await _dao.upsertSyncSession(
        SyncSessionsCompanion.insert(
          noteId: noteId,
          knownRevision: knownRevision,
          operationIds: jsonEncode(inFlightIds.toList()),
          startedAt: DateTime.now().toUtc().toIso8601String(),
        ),
      );
    });

    final request = SyncRequest(
      knownRevision: knownRevision,
      operations: ops
          .map((op) => OperationRequest(
                operationId: op.operationId,
                baseRevision: op.baseRevision,
                kind: op.kind,
                blockId: op.blockId,
                payload: parsePayload(op.payloadJson),
              ))
          .toList(),
      clientId: _clientId,
    );

    SyncResponse response;
    try {
      response = await _api.syncOperations(noteId, request);
    } catch (e) {
      rethrow;
    }

    return _processSyncResponse(noteId, response, inFlightIds, ops);
  }

  Future<SyncResult> _resumeSyncSession(
    String noteId,
    SyncSessionData session,
  ) async {
    final operationIds =
        List<String>.from(jsonDecode(session.operationIds) as List);

    final ops = await _dao.getPendingOperations(noteId, status: 'in_flight');
    final loadedIds = ops.map((o) => o.operationId).toSet();
    if (!_setEquals(loadedIds, operationIds.toSet())) {
      await _dao.updatePendingOpsStatus(noteId, 'in_flight', 'pending');
      await _dao.deleteSyncSession(noteId);
      return _syncPendingInner(noteId);
    }

    final request = SyncRequest(
      knownRevision: session.knownRevision,
      operations: ops
          .map((op) => OperationRequest(
                operationId: op.operationId,
                baseRevision: op.baseRevision,
                kind: op.kind,
                blockId: op.blockId,
                payload: parsePayload(op.payloadJson),
              ))
          .toList(),
      clientId: _clientId,
    );

    try {
      final response = await _api.syncOperations(noteId, request);
      return _processSyncResponse(noteId, response, operationIds.toSet(), ops);
    } catch (e) {
      rethrow;
    }
  }

  Future<SyncResult> _processSyncResponse(
    String noteId,
    SyncResponse response,
    Set<String> expectedIds,
    List<PendingNoteOperationData> inFlight,
  ) async {
    await _dao.runInTransaction(() async {
      final acceptedIds =
          response.accepted.map((a) => a.operationId).toSet();
      if (!_setEquals(acceptedIds, expectedIds)) {
        throw StateError(
          'Protocol error: accepted ${acceptedIds.length}/'
          '${expectedIds.length} ops. All-or-nothing required.',
        );
      }

      await _dao.deleteAccepted(expectedIds);
      final remaining =
          await _dao.getPendingOperations(noteId, status: 'pending');

      final canonical = response.canonicalDocument;
      if (canonical == null) {
        throw StateError(
          'Successful sync response must include canonicalDocument',
        );
      }

      final rebased = _rebaser.rebase(
        inFlight: inFlight,
        pending: remaining,
        remote: response.remoteOperations,
        finalRevision: response.finalRevision,
        acceptedOps: response.accepted,
      );
      await _dao.upsertNoteDocument(
        LocalNoteDocumentsCompanion.insert(
          noteId: noteId,
          revision: response.finalRevision,
          documentJson: encodeDocument(canonical),
          updatedAt: response.serverTime,
        ),
      );
      await _dao.deletePendingOpsByStatus(noteId, 'pending');
      for (int i = 0; i < rebased.length; i++) {
        final op = rebased[i];
        await _dao.insertPendingOperation(
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
        );
      }
      await _dao.deleteSyncSession(noteId);
    });

    return SyncResult(
      acceptedCount: response.accepted.length,
      acceptedOperationIds: expectedIds.toList(),
      finalRevision: response.finalRevision,
      remoteOperations: response.remoteOperations,
      canonicalDocument: NoteDocumentResponse(
        noteId: noteId,
        revision: response.finalRevision,
        document: response.canonicalDocument!,
        serverTime: response.serverTime,
      ),
    );
  }

  Future<SyncResult> _pollAndReconcileInner(String noteId) async {
    final activeSession = await _dao.getSyncSession(noteId);
    if (activeSession != null) {
      return _resumeSyncSession(noteId, activeSession);
    }

    final confirmed = await _dao.watchNoteDocument(noteId).first;
    final response =
        await _api.getOperationsSince(noteId, confirmed?.revision ?? 0);

    if (response.operations.isEmpty) {
      return SyncResult.empty();
    }

    final document = response.document;
    final revision = response.revision;
    if (document == null || revision == null) {
      throw StateError('Polling response must include document and revision');
    }

    final pending = await _dao.getPendingOperations(noteId, status: 'pending');
    final rebased = _rebaser.rebase(
      pending: pending,
      remote: response.operations,
      finalRevision: revision,
    );

    await _dao.runInTransaction(() async {
      await _dao.upsertNoteDocument(
        LocalNoteDocumentsCompanion.insert(
          noteId: noteId,
          revision: revision,
          documentJson: encodeDocument(document),
          updatedAt: DateTime.now().toUtc(),
        ),
      );
      await _dao.replacePendingOps(noteId, rebased);
    });

    return SyncResult(
      acceptedCount: 0,
      acceptedOperationIds: [],
      finalRevision: revision,
      remoteOperations: response.operations,
      canonicalDocument: NoteDocumentResponse(
        noteId: noteId,
        revision: revision,
        document: document,
        serverTime: DateTime.now().toUtc(),
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
    return jsonEncode(payload);
  }

  static String encodeDocument(Map<String, dynamic> document) {
    return jsonEncode(document);
  }
}
