import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/sync/note_document_projection.dart';
import 'package:supanotes/core/sync/note_sync_protocol.dart';
import 'package:supanotes/features/notes/editor/sync/note_operation_rebaser.dart';
import 'package:supanotes/features/notes/editor/sync/note_sync_client.dart';

final class NoteSyncReconciliation {
  const NoteSyncReconciliation({
    required this.response,
    required this.expectedOperationIds,
    required this.projection,
    required this.rebasedOperations,
  });

  final ValidatedSyncResponse response;
  final Set<String> expectedOperationIds;
  final NoteDocumentProjection projection;
  final List<PendingNoteOperationData> rebasedOperations;
}

final class NotePollReconciliation {
  const NotePollReconciliation({
    required this.response,
    required this.projection,
    required this.rebasedOperations,
  });

  final ValidatedPollResponse response;
  final NoteDocumentProjection projection;
  final List<PendingNoteOperationData> rebasedOperations;
}

/// Pure boundary between protocol validation, OT rebase and document
/// projection. It has no database or network side effects.
final class NoteSyncReconciler {
  NoteSyncReconciler({
    required NoteOperationRebaser rebaser,
    NoteSyncProtocolValidator protocol = const NoteSyncProtocolValidator(),
    NoteDocumentProjector? projector,
  }) : _protocol = protocol,
       _projector = projector ?? NoteDocumentProjector(),
       _rebaser = rebaser;

  final NoteSyncProtocolValidator _protocol;
  final NoteDocumentProjector _projector;
  final NoteOperationRebaser _rebaser;

  NoteSyncReconciliation reconcilePending({
    required String noteId,
    required List<PendingNoteOperationData> inFlight,
    required List<PendingNoteOperationData> pending,
    required SyncResponse response,
  }) {
    final validated = _protocol.validatePendingResponse(
      noteId: noteId,
      expectedOperations: inFlight
          .map(
            (operation) => PendingOperationIdentity(
              operationId: operation.operationId,
              kind: operation.kind,
              blockId: operation.blockId,
            ),
          )
          .toList(growable: false),
      response: response,
    );
    final rebased = _rebaser.rebase(
      inFlight: inFlight,
      pending: pending,
      remote: response.remoteOperations,
      finalRevision: response.finalRevision,
      acceptedOps: response.accepted,
    );
    final projection = _projector.project(
      snapshot: validated.canonicalDocument,
      pendingOperations: rebased,
    );
    return NoteSyncReconciliation(
      response: validated,
      expectedOperationIds: validated.expectedOperationIds,
      projection: projection,
      rebasedOperations: rebased,
    );
  }

  NotePollReconciliation reconcilePoll({
    required String noteId,
    required int fromRevision,
    required OperationsListResponse response,
    required List<PendingNoteOperationData> pending,
  }) {
    final validated = _protocol.validatePollResponse(
      noteId: noteId,
      fromRevision: fromRevision,
      response: response,
    );
    final rebased = _rebaser.rebase(
      pending: pending,
      remote: validated.operations,
      finalRevision: validated.revision,
    );
    final projection = _projector.project(
      snapshot: validated.document,
      pendingOperations: rebased,
    );
    return NotePollReconciliation(
      response: validated,
      projection: projection,
      rebasedOperations: rebased,
    );
  }

  NoteDocumentProjection projectMaterialized(String documentJson) {
    return _projector.projectMaterialized(documentJson);
  }
}
