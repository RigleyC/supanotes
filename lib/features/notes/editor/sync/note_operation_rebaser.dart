import 'dart:convert';

import 'package:dart_quill_delta/dart_quill_delta.dart' as quill;

import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/features/notes/editor/sync/note_operation_contract.dart';
import 'package:supanotes/features/notes/editor/sync/note_sync_client.dart';

class NoteOp {

  NoteOp({
    required this.operationId,
    required this.actorId,
    required this.kind, required this.blockId, required this.payload, this.revision,
    this.cachedDelta,
  });

  factory NoteOp.fromData({
    required String operationId,
    required String actorId,
    required String kind, required String? blockId, required Map<String, dynamic> payload, int? revision,
    quill.Delta? cachedDelta,
  }) {
    var delta = cachedDelta;
    if (delta == null &&
        kind == NoteOperationKind.textDelta.wireName &&
        payload.containsKey('ops')) {
      final ops = payload['ops'];
      if (ops is List) {
        delta = quill.Delta.fromJson(ops);
      }
    }
    return NoteOp(
      operationId: operationId,
      actorId: actorId,
      revision: revision,
      kind: kind,
      blockId: blockId,
      payload: payload,
      cachedDelta: delta,
    );
  }
  final String operationId;
  final String actorId;
  final int? revision;
  final String kind;
  final String? blockId;
  final Map<String, dynamic> payload;
  final quill.Delta? cachedDelta;
}

class NoteOperationRebaser {

  NoteOperationRebaser({required this.localActorId});
  final String localActorId;

  /// Pure rebase: transforms [pending] ops against [remote] ops, assigns
  /// sequential baseRevisions from [finalRevision], and omits no-ops.
  List<PendingNoteOperationData> rebase({
    required List<PendingNoteOperationData> pending, required List<Operation> remote, required int finalRevision, List<PendingNoteOperationData>? inFlight,
    List<AcceptedOperation>? acceptedOps,
  }) {
    final acceptedRevisions = _acceptedRevisions(acceptedOps);
    var currentRemote = _toNoteOperations(remote);
    currentRemote = _transformRemoteAgainstInFlight(
      inFlight: inFlight,
      remote: currentRemote,
      acceptedRevisions: acceptedRevisions,
    );

    final result = <PendingNoteOperationData>[];
    var activeRemote = currentRemote;

    for (final pendingData in pending) {
      if (acceptedRevisions.containsKey(pendingData.operationId)) {
        continue;
      }

      final rebased = _rebasePendingOperation(
        pendingData: pendingData,
        activeRemote: activeRemote,
      );
      if (rebased == null) continue;

      activeRemote = rebased.remote;
      result.add(
        _buildRebasedOperation(
          pendingData: pendingData,
          operation: rebased.operation,
          finalRevision: finalRevision,
          ordinal: result.length,
        ),
      );
    }
    return result;
  }

  Map<String, int> _acceptedRevisions(List<AcceptedOperation>? acceptedOps) {
    if (acceptedOps == null) return {};
    return {
      for (final accepted in acceptedOps)
        accepted.operationId: accepted.revision,
    };
  }

  List<NoteOp> _toNoteOperations(List<Operation> operations) {
    return operations
        .map(
          (operation) => NoteOp.fromData(
            operationId: operation.operationId,
            actorId: operation.actorId,
            revision: operation.revision,
            kind: operation.kind,
            blockId: operation.blockId,
            payload: operation.payload,
          ),
        )
        .toList();
  }

  List<NoteOp> _transformRemoteAgainstInFlight({
    required List<PendingNoteOperationData>? inFlight,
    required List<NoteOp> remote,
    required Map<String, int> acceptedRevisions,
  }) {
    var currentRemote = remote;
    if (inFlight == null || inFlight.isEmpty) return currentRemote;

    for (final inFlightData in inFlight) {
      final payload =
          jsonDecode(inFlightData.payloadJson) as Map<String, dynamic>;
      final inFlightOp = NoteOp.fromData(
        operationId: inFlightData.operationId,
        actorId: localActorId,
        kind: inFlightData.kind,
        blockId: inFlightData.blockId,
        payload: payload,
      );
      final acceptedRevision = acceptedRevisions[inFlightOp.operationId];
      final transformedRemote = <NoteOp>[];

      for (final remoteOp in currentRemote) {
        if (acceptedRevision != null &&
            remoteOp.revision != null &&
            remoteOp.revision! < acceptedRevision) {
          final localKey = '$localActorId:${inFlightOp.operationId}';
          final remoteKey = '${remoteOp.actorId}:${remoteOp.operationId}';
          final remoteHasPriority = remoteKey.compareTo(localKey) > 0;
          final transformed = _transformOp(
            remoteOp,
            inFlightOp,
            remoteHasPriority,
          );
          if (transformed != null) transformedRemote.add(transformed);
        } else {
          transformedRemote.add(remoteOp);
        }
      }
      currentRemote = transformedRemote;
    }
    return currentRemote;
  }

  ({NoteOp operation, List<NoteOp> remote})? _rebasePendingOperation({
    required PendingNoteOperationData pendingData,
    required List<NoteOp> activeRemote,
  }) {
    var operation = NoteOp.fromData(
      operationId: pendingData.operationId,
      actorId: localActorId,
      kind: pendingData.kind,
      blockId: pendingData.blockId,
      payload: jsonDecode(pendingData.payloadJson) as Map<String, dynamic>,
    );
    final nextRemote = <NoteOp>[];

    for (final remoteOp in activeRemote) {
      final localKey = '$localActorId:${operation.operationId}';
      final remoteKey = '${remoteOp.actorId}:${remoteOp.operationId}';
      final localHasPriority = localKey.compareTo(remoteKey) > 0;
      final transformedOperation = _transformOp(
        operation,
        remoteOp,
        localHasPriority,
      );
      if (transformedOperation == null) return null;

      final transformedRemote = _transformOp(
        remoteOp,
        operation,
        !localHasPriority,
      );
      if (transformedRemote != null) nextRemote.add(transformedRemote);
      operation = transformedOperation;
    }

    return (operation: operation, remote: nextRemote);
  }

  PendingNoteOperationData _buildRebasedOperation({
    required PendingNoteOperationData pendingData,
    required NoteOp operation,
    required int finalRevision,
    required int ordinal,
  }) {
    return PendingNoteOperationData(
      operationId: operation.operationId,
      noteId: pendingData.noteId,
      baseRevision: finalRevision + ordinal,
      ordinal: ordinal,
      kind: operation.kind,
      blockId: operation.blockId,
      payloadJson: jsonEncode(operation.payload),
      createdAt: pendingData.createdAt,
      lastAttemptAt: pendingData.lastAttemptAt,
      attemptCount: pendingData.attemptCount,
      status: pendingData.status,
    );
  }

  /// Transforms `opToTransform` against `appliedOp`.
  /// Returns null if `opToTransform` becomes a no-op.
  NoteOp? _transformOp(
    NoteOp opToTransform,
    NoteOp appliedOp,
    bool opToTransformHasPriority,
  ) {
    if (_remoteDeleteRemovesOperation(opToTransform, appliedOp)) {
      return null;
    }

    if (_isTextDeltaPair(opToTransform, appliedOp)) {
      return _transformTextDelta(
        opToTransform,
        appliedOp,
        opToTransformHasPriority,
      );
    }

    final payload = Map<String, dynamic>.from(opToTransform.payload);
    switch (opToTransform.kind) {
      case NoteOperationWireNames.createBlock:
        _transformCreateBlock(payload, appliedOp, opToTransformHasPriority);
      case NoteOperationWireNames.moveBlock:
        if (!_transformMoveBlock(
          payload,
          appliedOp,
          opToTransformHasPriority,
        )) {
          return null;
        }
      case NoteOperationWireNames.deleteBlock:
      case NoteOperationWireNames.setBlockType:
        if (_sameBlockWasDeleted(opToTransform, appliedOp)) return null;
    }

    return NoteOp(
      operationId: opToTransform.operationId,
      actorId: opToTransform.actorId,
      revision: opToTransform.revision,
      kind: opToTransform.kind,
      blockId: opToTransform.blockId,
      payload: payload,
    );
  }

  bool _remoteDeleteRemovesOperation(NoteOp operation, NoteOp appliedOp) {
    return appliedOp.kind == NoteOperationKind.deleteBlock.wireName &&
        appliedOp.blockId != null &&
        appliedOp.blockId == operation.blockId;
  }

  bool _isTextDeltaPair(NoteOp operation, NoteOp appliedOp) {
    return operation.kind == NoteOperationKind.textDelta.wireName &&
        appliedOp.kind == NoteOperationKind.textDelta.wireName;
  }

  NoteOp _transformTextDelta(
    NoteOp operation,
    NoteOp appliedOp,
    bool operationHasPriority,
  ) {
    if (operation.blockId != appliedOp.blockId) return operation;

    final operationOps = operation.payload['ops'];
    final appliedOps = appliedOp.payload['ops'];
    if (operationOps == null || appliedOps == null) return operation;

    final operationDelta =
        operation.cachedDelta ??
        quill.Delta.fromJson(operationOps as List<dynamic>);
    final appliedDelta =
        appliedOp.cachedDelta ??
        quill.Delta.fromJson(appliedOps as List<dynamic>);
    final transformedDelta = appliedDelta.transform(
      operationDelta,
      !operationHasPriority,
    );
    final payload = Map<String, dynamic>.from(operation.payload);
    payload['ops'] = transformedDelta.toJson();

    return NoteOp.fromData(
      operationId: operation.operationId,
      actorId: operation.actorId,
      revision: operation.revision,
      kind: operation.kind,
      blockId: operation.blockId,
      payload: payload,
      cachedDelta: transformedDelta,
    );
  }

  void _transformCreateBlock(
    Map<String, dynamic> payload,
    NoteOp appliedOp,
    bool operationHasPriority,
  ) {
    final afterBlockId = payload['afterBlockId'] as String?;
    if (appliedOp.kind == NoteOperationKind.deleteBlock.wireName &&
        afterBlockId == appliedOp.blockId) {
      payload['afterBlockId'] = null;
    }
    if (appliedOp.kind != NoteOperationKind.createBlock.wireName) return;

    final appliedAfterBlockId = appliedOp.payload['afterBlockId'] as String?;
    if (afterBlockId != null && afterBlockId == appliedAfterBlockId) {
      if (!operationHasPriority) {
        payload['afterBlockId'] = appliedOp.blockId;
      }
    }
  }

  bool _transformMoveBlock(
    Map<String, dynamic> payload,
    NoteOp appliedOp,
    bool operationHasPriority,
  ) {
    final targetId = payload['blockId'] as String?;
    if (appliedOp.kind == NoteOperationKind.deleteBlock.wireName &&
        targetId == appliedOp.blockId) {
      return false;
    }

    final afterBlockId = payload['afterBlockId'] as String?;
    if (appliedOp.kind == NoteOperationKind.deleteBlock.wireName &&
        afterBlockId == appliedOp.blockId) {
      payload['afterBlockId'] = null;
    }
    if (appliedOp.kind != NoteOperationKind.moveBlock.wireName) return true;

    final appliedTargetId = appliedOp.payload['blockId'] as String?;
    if (targetId == appliedTargetId && !operationHasPriority) return false;
    return true;
  }

  bool _sameBlockWasDeleted(NoteOp operation, NoteOp appliedOp) {
    return appliedOp.kind == NoteOperationKind.deleteBlock.wireName &&
        operation.blockId == appliedOp.blockId;
  }
}
