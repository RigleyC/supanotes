import 'package:supanotes/features/notes/editor/sync/note_sync_client.dart';

final class ValidatedSyncResponse {
  const ValidatedSyncResponse({
    required this.response,
    required this.expectedOperationIds,
    required this.canonicalDocument,
  });

  final SyncResponse response;
  final Set<String> expectedOperationIds;
  final Map<String, dynamic> canonicalDocument;
}

final class ValidatedPollResponse {
  const ValidatedPollResponse({
    required this.operations,
    required this.document,
    required this.revision,
  });

  final List<Operation> operations;
  final Map<String, dynamic> document;
  final int revision;
}

/// Validates the wire envelope before any local sync state is changed.
final class NoteSyncProtocolValidator {
  const NoteSyncProtocolValidator();

  ValidatedSyncResponse validatePendingResponse({
    required String noteId,
    required List<PendingOperationIdentity> expectedOperations,
    required SyncResponse response,
  }) {
    final expectedById = <String, PendingOperationIdentity>{};
    for (final operation in expectedOperations) {
      if (expectedById.containsKey(operation.operationId)) {
        throw StateError(
          'Duplicate expected operationId ${operation.operationId}',
        );
      }
      expectedById[operation.operationId] = operation;
    }

    final acceptedIds = <String>{};
    for (final accepted in response.accepted) {
      if (!acceptedIds.add(accepted.operationId)) {
        throw StateError(
          'Sync response contains duplicate operationId '
          '${accepted.operationId}',
        );
      }
      final expected = expectedById[accepted.operationId];
      if (expected == null) {
        throw StateError(
          'Sync response accepted unknown operationId '
          '${accepted.operationId}',
        );
      }
      if (expected.kind != accepted.kind ||
          expected.blockId != accepted.blockId) {
        throw StateError(
          'Sync response changed operation identity '
          '${accepted.operationId}',
        );
      }
    }

    final expectedIds = expectedById.keys.toSet();
    if (!_setEquals(acceptedIds, expectedIds)) {
      throw StateError(
        'Protocol error: accepted ${acceptedIds.length}/'
        '${expectedIds.length} ops. All-or-nothing required.',
      );
    }
    if (response.finalRevision < 0) {
      throw StateError('Sync response has a negative final revision');
    }

    final canonical = response.canonicalDocument;
    if (canonical == null) {
      throw StateError(
        'Successful sync response must include canonicalDocument',
      );
    }
    _validateRemoteOperations(noteId, response.remoteOperations);
    return ValidatedSyncResponse(
      response: response,
      expectedOperationIds: expectedIds,
      canonicalDocument: canonical,
    );
  }

  ValidatedPollResponse validatePollResponse({
    required String noteId,
    required int fromRevision,
    required OperationsListResponse response,
  }) {
    final document = response.document;
    final revision = response.revision;
    if (document == null || revision == null) {
      throw StateError('Polling response must include document and revision');
    }
    if (revision < fromRevision) {
      throw StateError(
        'Polling response moved revision backwards '
        '($revision < $fromRevision)',
      );
    }
    _validateRemoteOperations(noteId, response.operations);
    return ValidatedPollResponse(
      operations: response.operations,
      document: document,
      revision: revision,
    );
  }

  void _validateRemoteOperations(String noteId, List<Operation> operations) {
    final ids = <String>{};
    for (final operation in operations) {
      if (operation.noteId != noteId) {
        throw StateError(
          'Remote operation ${operation.operationId} belongs to '
          '${operation.noteId}, expected $noteId',
        );
      }
      if (!ids.add(operation.operationId)) {
        throw StateError(
          'Remote operations contain duplicate operationId '
          '${operation.operationId}',
        );
      }
    }
  }

  static bool _setEquals(Set<String> left, Set<String> right) {
    if (left.length != right.length) return false;
    return left.every(right.contains);
  }
}

final class PendingOperationIdentity {
  const PendingOperationIdentity({
    required this.operationId,
    required this.kind,
    required this.blockId,
  });

  final String operationId;
  final String kind;
  final String? blockId;
}
