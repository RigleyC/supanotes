import 'dart:convert';

import 'package:dart_quill_delta/dart_quill_delta.dart' as quill;

import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/features/notes/data/note_sync_client.dart';

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
    if (delta == null && kind == 'text_delta' && payload.containsKey('ops')) {
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
    final acceptedRevisions = <String, int>{};
    if (acceptedOps != null) {
      for (final a in acceptedOps) {
        acceptedRevisions[a.operationId] = a.revision;
      }
    }

    var currentRemote = remote
        .map(
          (r) => NoteOp.fromData(
            operationId: r.operationId,
            actorId: r.actorId,
            revision: r.revision,
            kind: r.kind,
            blockId: r.blockId,
            payload: r.payload,
          ),
        )
        .toList();

    if (inFlight != null && inFlight.isNotEmpty) {
      for (final inFlightData in inFlight) {
        final payload = jsonDecode(inFlightData.payloadJson) as Map<String, dynamic>;
        final inFlightOp = NoteOp.fromData(
          operationId: inFlightData.operationId,
          actorId: localActorId,
          kind: inFlightData.kind,
          blockId: inFlightData.blockId,
          payload: payload,
        );

        final acceptedRev = acceptedRevisions[inFlightOp.operationId];
        final newRemote = <NoteOp>[];
        for (final r in currentRemote) {
          if (acceptedRev != null &&
              r.revision != null &&
              r.revision! < acceptedRev) {
            final localKey = '$localActorId:${inFlightOp.operationId}';
            final remoteKey = '${r.actorId}:${r.operationId}';
            final rHasPriority = remoteKey.compareTo(localKey) > 0;

            final transformed = _transformOp(r, inFlightOp, rHasPriority);
            if (transformed != null) {
              newRemote.add(transformed);
            }
          } else {
            newRemote.add(r);
          }
        }
        currentRemote = newRemote;
      }
    }

    final result = <PendingNoteOperationData>[];
    var activeRemote = currentRemote;

    for (int i = 0; i < pending.length; i++) {
      final pendingData = pending[i];
      if (acceptedRevisions.containsKey(pendingData.operationId)) {
        continue;
      }

      var pOp = NoteOp.fromData(
        operationId: pendingData.operationId,
        actorId: localActorId,
        kind: pendingData.kind,
        blockId: pendingData.blockId,
        payload: jsonDecode(pendingData.payloadJson) as Map<String, dynamic>,
      );

      bool dropped = false;
      final nextRemote = <NoteOp>[];

      for (final r in activeRemote) {
        final localKey = '$localActorId:${pOp.operationId}';
        final remoteKey = '${r.actorId}:${r.operationId}';
        final pHasPriority = localKey.compareTo(remoteKey) > 0;

        final transformedP = _transformOp(pOp, r, pHasPriority);
        if (transformedP == null) {
          dropped = true;
          break;
        }

        final transformedR = _transformOp(r, pOp, !pHasPriority);
        if (transformedR != null) {
          nextRemote.add(transformedR);
        }

        pOp = transformedP;
      }

      if (dropped) continue;
      activeRemote = nextRemote;

      result.add(
        PendingNoteOperationData(
          operationId: pOp.operationId,
          noteId: pendingData.noteId,
          baseRevision: finalRevision + result.length,
          ordinal: result.length,
          kind: pOp.kind,
          blockId: pOp.blockId,
          payloadJson: jsonEncode(pOp.payload),
          createdAt: pendingData.createdAt,
          lastAttemptAt: pendingData.lastAttemptAt,
          attemptCount: pendingData.attemptCount,
          status: pendingData.status,
        ),
      );
    }
    return result;
  }

  NoteOp? transformOp(
    NoteOp opToTransform,
    NoteOp appliedOp,
    bool opToTransformHasPriority,
  ) {
    return _transformOp(opToTransform, appliedOp, opToTransformHasPriority);
  }

  /// Transforms `opToTransform` against `appliedOp`.
  /// Returns null if `opToTransform` becomes a no-op.
  NoteOp? _transformOp(
    NoteOp opToTransform,
    NoteOp appliedOp,
    bool opToTransformHasPriority,
  ) {
    if (appliedOp.kind == 'delete_block' &&
        appliedOp.blockId != null &&
        appliedOp.blockId == opToTransform.blockId) {
      return null;
    }

    if (opToTransform.kind == 'text_delta' && appliedOp.kind == 'text_delta') {
      if (opToTransform.blockId != appliedOp.blockId) return opToTransform;

      final opToTransformOps = opToTransform.payload['ops'];
      final appliedOps = appliedOp.payload['ops'];
      if (opToTransformOps == null || appliedOps == null) return opToTransform;

      final opToTransformDelta = opToTransform.cachedDelta ??
          quill.Delta.fromJson(opToTransformOps as List<dynamic>);
      final appliedDelta = appliedOp.cachedDelta ??
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

    if (kind == 'create_block') {
      final afterBlockId = payload['afterBlockId'] as String?;
      if (rKind == 'delete_block' && afterBlockId == appliedOp.blockId) {
        payload['afterBlockId'] = null;
      }
      if (rKind == 'create_block') {
        final rAfter = rPayload['afterBlockId'] as String?;
        if (afterBlockId != null && afterBlockId == rAfter) {
          if (!opToTransformHasPriority) {
            payload['afterBlockId'] = appliedOp.blockId;
          }
        }
      }
    }

    if (kind == 'move_block') {
      final targetId = payload['blockId'] as String?;
      if (rKind == 'delete_block' && targetId == appliedOp.blockId) {
        return null;
      }
      final afterBlockId = payload['afterBlockId'] as String?;
      if (rKind == 'delete_block' && afterBlockId == appliedOp.blockId) {
        payload['afterBlockId'] = null;
      }
      if (rKind == 'move_block') {
        final rTarget = rPayload['blockId'] as String?;
        if (targetId == rTarget) {
          if (!opToTransformHasPriority) {
            return null;
          }
        }
      }
    }

    if (kind == 'delete_block') {
      if (rKind == 'delete_block' &&
          opToTransform.blockId == appliedOp.blockId) {
        return null;
      }
    }

    if (kind == 'set_block_type') {
      if (rKind == 'delete_block' &&
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
