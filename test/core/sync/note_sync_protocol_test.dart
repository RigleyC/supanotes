import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/core/sync/note_sync_protocol.dart';
import 'package:supanotes/features/notes/editor/sync/note_sync_client.dart';

void main() {
  const validator = NoteSyncProtocolValidator();

  test('rejects an accepted operation with a changed identity', () {
    final response = SyncResponse(
      accepted: [
        AcceptedOperation(
          operationId: 'op-1',
          revision: 4,
          kind: 'delete_block',
        ),
      ],
      finalRevision: 4,
      remoteOperations: const [],
      canonicalDocument: const {'schemaVersion': 1, 'blocks': []},
      serverTime: DateTime.utc(2026, 9, 2),
    );

    expect(
      () => validator.validatePendingResponse(
        noteId: 'note-1',
        expectedOperations: const [
          PendingOperationIdentity(
            operationId: 'op-1',
            kind: 'create_block',
            blockId: null,
          ),
        ],
        response: response,
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('rejects a real duplicate in the expected operation list', () {
    final response = SyncResponse(
      accepted: [
        AcceptedOperation(
          operationId: 'op-1',
          revision: 4,
          kind: 'create_block',
        ),
      ],
      finalRevision: 4,
      remoteOperations: const [],
      canonicalDocument: const {'schemaVersion': 1, 'blocks': []},
      serverTime: DateTime.utc(2026, 9, 2),
    );

    expect(
      () => validator.validatePendingResponse(
        noteId: 'note-1',
        expectedOperations: const [
          PendingOperationIdentity(
            operationId: 'op-1',
            kind: 'create_block',
            blockId: null,
          ),
          PendingOperationIdentity(
            operationId: 'op-1',
            kind: 'create_block',
            blockId: null,
          ),
        ],
        response: response,
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('rejects a poll containing an operation for another note', () {
    final operation = Operation(
      operationId: 'remote-1',
      noteId: 'other-note',
      revision: 2,
      baseRevision: 1,
      actorId: 'user-2',
      kind: 'text_delta',
      payload: const {'ops': []},
      createdAt: DateTime.utc(2026, 9, 2),
    );

    expect(
      () => validator.validatePollResponse(
        noteId: 'note-1',
        fromRevision: 1,
        response: OperationsListResponse(
          operations: [operation],
          document: const {'schemaVersion': 1, 'blocks': []},
          revision: 2,
        ),
      ),
      throwsA(isA<StateError>()),
    );
  });
}
