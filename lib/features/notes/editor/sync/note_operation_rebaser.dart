import 'dart:convert';

import 'package:dart_quill_delta/dart_quill_delta.dart' as quill;

import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/features/notes/editor/sync/note_operation_contract.dart';
import 'package:supanotes/features/notes/editor/sync/note_sync_client.dart';

class NoteOp {
  final String operationId;
  final String actorId;
  final int? revision;
  final String kind;
  final String? blockId;
  final Map<String, dynamic> payload;
  final quill.Delta? cachedDelta;

  NoteOp({
    required this.operationId,
    required this.actorId,
    this.revision,
    required this.kind,
    required this.blockId,
    required this.payload,
    this.cachedDelta,
  });

  factory NoteOp.fromData({
    required String operationId,
    required String actorId,
    int? revision,
    required String kind,
    required String? blockId,
    required Map<String, dynamic> payload,
    quill.Delta? cachedDelta,
  }) {
    quill.Delta? delta = cachedDelta;
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
}

class NoteOperationRebaser {
  final String localActorId;

  NoteOperationRebaser({required this.localActorId});

  /// Pure rebase: transforms [pending] ops against [remote] ops, assigns
  /// sequential baseRevisions from [finalRevision], and omits no-ops.
  List<PendingNoteOperationData> rebase({
    List<PendingNoteOperationData>? inFlight,
    required List<PendingNoteOperationData> pending,
    required List<Operation> remote,
    required int finalRevision,
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
    if (appliedOp.kind == NoteOperationKind.deleteBlock.wireName &&
        appliedOp.blockId != null &&
        appliedOp.blockId == opToTransform.blockId) {
      return null;
    }

    if (opToTransform.kind == NoteOperationKind.textDelta.wireName &&
        appliedOp.kind == NoteOperationKind.textDelta.wireName) {
      if (opToTransform.blockId != appliedOp.blockId) return opToTransform;

      final opToTransformOps = opToTransform.payload['ops'];
      final appliedOps = appliedOp.payload['ops'];
      if (opToTransformOps == null || appliedOps == null) return opToTransform;

      final opToTransformDelta =
          opToTransform.cachedDelta ??
          quill.Delta.fromJson(opToTransformOps as List<dynamic>);
      final appliedDelta =
          appliedOp.cachedDelta ??
          quill.Delta.fromJson(appliedOps as List<dynamic>);

      final transformedDelta = appliedDelta.transform(
        opToTransformDelta,
        !opToTransformHasPriority,
      );

      final newPayload = Map<String, dynamic>.from(opToTransform.payload);
      newPayload['ops'] = transformedDelta.toJson();

      return NoteOp.fromData(
        operationId: opToTransform.operationId,
        actorId: opToTransform.actorId,
        revision: opToTransform.revision,
        kind: opToTransform.kind,
        blockId: opToTransform.blockId,
        payload: newPayload,
        cachedDelta: transformedDelta,
      );
    }

    final payload = Map<String, dynamic>.from(opToTransform.payload);
    final kind = opToTransform.kind;
    final rKind = appliedOp.kind;
    final rPayload = appliedOp.payload;

    if (kind == NoteOperationKind.createBlock.wireName) {
      final afterBlockId = payload['afterBlockId'] as String?;
      if (rKind == NoteOperationKind.deleteBlock.wireName &&
          afterBlockId == appliedOp.blockId) {
        payload['afterBlockId'] = null;
      }
      if (rKind == NoteOperationKind.createBlock.wireName) {
        final rAfter = rPayload['afterBlockId'] as String?;
        if (afterBlockId != null && afterBlockId == rAfter) {
          if (!opToTransformHasPriority) {
            payload['afterBlockId'] = appliedOp.blockId;
          }
        }
      }
    }

    if (kind == NoteOperationKind.moveBlock.wireName) {
      final targetId = payload['blockId'] as String?;
      if (rKind == NoteOperationKind.deleteBlock.wireName &&
          targetId == appliedOp.blockId) {
        return null;
      }
      final afterBlockId = payload['afterBlockId'] as String?;
      if (rKind == NoteOperationKind.deleteBlock.wireName &&
          afterBlockId == appliedOp.blockId) {
        payload['afterBlockId'] = null;
      }
      if (rKind == NoteOperationKind.moveBlock.wireName) {
        final rTarget = rPayload['blockId'] as String?;
        if (targetId == rTarget) {
          if (!opToTransformHasPriority) {
            return null;
          }
        }
      }
    }

    if (kind == NoteOperationKind.deleteBlock.wireName) {
      if (rKind == NoteOperationKind.deleteBlock.wireName &&
          opToTransform.blockId == appliedOp.blockId) {
        return null;
      }
    }

    if (kind == NoteOperationKind.setBlockType.wireName) {
      if (rKind == NoteOperationKind.deleteBlock.wireName &&
          opToTransform.blockId == appliedOp.blockId) {
        return null;
      }
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
}
