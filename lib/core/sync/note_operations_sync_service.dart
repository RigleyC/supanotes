import 'dart:convert';
import 'dart:developer' as dev;

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:supanotes/core/database/daos/note_operations_dao.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/features/notes/data/note_operations_api.dart';

class SyncResult {
  final int acceptedCount;
  final int rejectedCount;
  final int finalRevision;

  SyncResult({
    required this.acceptedCount,
    required this.rejectedCount,
    required this.finalRevision,
  });
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

class _NoteSyncState {
  int confirmedRevision;
  List<PendingNoteOperationData> pendingOperations;

  _NoteSyncState({
    required this.confirmedRevision,
    List<PendingNoteOperationData>? pendingOperations,
  }) : pendingOperations = pendingOperations ?? [];
}

class NoteOperationsSyncService {
  final NoteOperationsApiClient _api;
  final NoteOperationsDao _dao;
  final String _clientId;
  final Uuid _uuid = const Uuid();

  final Map<String, _NoteSyncState> _noteStates = {};

  NoteOperationsSyncService({
    required NoteOperationsApiClient api,
    required NoteOperationsDao dao,
    required String clientId,
  })  : _api = api,
        _dao = dao,
        _clientId = clientId;

  String get clientId => _clientId;

  Future<SyncResult> syncPending(String noteId) async {
    final pending = await _dao.getPendingOperations(noteId);
    if (pending.isEmpty) {
      final doc = await _dao.watchNoteDocument(noteId).first;
      final revision = doc?.revision ?? 0;
      return SyncResult(
        acceptedCount: 0,
        rejectedCount: 0,
        finalRevision: revision,
      );
    }

    final doc = await _dao.watchNoteDocument(noteId).first;
    final knownRevision = doc?.revision ?? 0;

    final request = SyncRequest(
      knownRevision: knownRevision,
      operations: pending
          .map(
            (op) => OperationRequest(
              operationId: op.operationId,
              baseRevision: op.baseRevision,
              kind: op.kind,
              blockId: op.blockId,
              payload: NoteOperationsSyncService.parsePayload(op.payloadJson),
            ),
          )
          .toList(),
      clientId: _clientId,
    );

    try {
      final response = await _api.syncOperations(noteId, request);

      for (final accepted in response.accepted) {
        await _dao.deletePendingOperation(accepted.operationId);
      }

      if (response.remoteOperations.isNotEmpty) {
        final newDoc = await _api.getDocument(noteId);
        await _dao.upsertNoteDocument(
          LocalNoteDocumentsCompanion.insert(
            noteId: newDoc.noteId,
            revision: newDoc.revision,
            documentJson: NoteOperationsSyncService.encodeDocument(newDoc.document),
            updatedAt: newDoc.serverTime,
          ),
        );

        if (_noteStates.containsKey(noteId)) {
          _noteStates[noteId]!.confirmedRevision = newDoc.revision;
        }
      } else {
        final existing = await _dao.watchNoteDocument(noteId).first;
        await _dao.upsertNoteDocument(
          LocalNoteDocumentsCompanion(
            noteId: Value(noteId),
            revision: Value(response.finalRevision),
            updatedAt: Value(DateTime.now().toUtc()),
            documentJson: Value(existing?.documentJson ?? ''),
          ),
        );

        if (_noteStates.containsKey(noteId)) {
          _noteStates[noteId]!.confirmedRevision = response.finalRevision;
        }
      }

      return SyncResult(
        acceptedCount: response.accepted.length,
        rejectedCount: pending.length - response.accepted.length,
        finalRevision: response.finalRevision,
      );
    } on NoteOperationsException catch (e) {
      dev.log(
        '[NoteOperationsSyncService] Sync failed for note=$noteId: $e',
        name: 'NoteOperationsSync',
      );

      for (final op in pending) {
        await _dao.incrementAttempt(op.operationId);
        await _dao.insertSyncError(
          NoteSyncErrorsCompanion.insert(
            operationId: op.operationId,
            noteId: noteId,
            errorCode: e.errorCode,
            message: e.message,
            payloadJson: op.payloadJson,
            createdAt: DateTime.now().toUtc(),
          ),
        );
      }

      rethrow;
    }
  }

  Future<void> pollRemoteOperations(String noteId) async {
    final doc = await _dao.watchNoteDocument(noteId).first;
    final afterRevision = doc?.revision ?? 0;

    try {
      final response = await _api.getOperationsSince(noteId, afterRevision);
      if (response.operations.isEmpty) return;

      final newDoc = await _api.getDocument(noteId);
      await _dao.upsertNoteDocument(
        LocalNoteDocumentsCompanion.insert(
          noteId: newDoc.noteId,
          revision: newDoc.revision,
            documentJson: NoteOperationsSyncService.encodeDocument(newDoc.document),
          updatedAt: newDoc.serverTime,
        ),
      );

      if (_noteStates.containsKey(noteId)) {
        _noteStates[noteId]!.confirmedRevision = newDoc.revision;
      }
    } on NoteOperationsException catch (e) {
      dev.log(
        '[NoteOperationsSyncService] Poll failed for note=$noteId: $e',
        name: 'NoteOperationsSync',
      );
    }
  }

  Future<void> enqueueOperation(
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
        payloadJson: NoteOperationsSyncService.encodePayload(request.payload),
        createdAt: DateTime.now().toUtc(),
      ),
    );
  }

  Future<LocalNoteDocumentData?> getConfirmedDocument(String noteId) {
    return _dao.watchNoteDocument(noteId).first;
  }

  Future<List<PendingNoteOperationData>> getPendingOperations(
    String noteId,
  ) {
    return _dao.getPendingOperations(noteId);
  }

  Stream<List<PendingNoteOperationData>> watchPendingOperations(
    String noteId,
  ) {
    return _dao.watchPendingOperations(noteId);
  }

  String generateOperationId() => _uuid.v4();

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
