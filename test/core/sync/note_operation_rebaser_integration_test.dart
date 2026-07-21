import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/features/notes/data/note_operations_api.dart';
import 'package:supanotes/features/notes/domain/note_operation_rebaser.dart';

void main() {
  group('NoteOperationRebaser Integration', () {
    test(
      'rebases pending ops against remote ops that concurrent with in-flight ops',
      () {
        final rebaser = NoteOperationRebaser(localActorId: 'client1');

        // Scenario:
        // We have a block 'b1' with text 'abc'.
        // P1 (inFlight): client1 deletes 'c' (retain 2, delete 1).
        // P2 (pending): client1 inserts 'X' at end (retain 2, insert 'X'). (Created on top of P1).
        // R1 (remote): client2 inserts 'Y' at index 1 (retain 1, insert 'Y'). (Concurrent to P1).

        final inFlight = [
          PendingNoteOperationData(
            operationId: 'op1',
            noteId: 'n1',
            baseRevision: 10,
            ordinal: 0,
            kind: 'text_delta',
            blockId: 'b1',
            payloadJson: jsonEncode({
              'ops': [
                {'retain': 2},
                {'delete': 1},
              ],
            }),
            createdAt: DateTime.now(),
            status: 'in_flight',
            attemptCount: 1,
          ),
        ];

        final pending = [
          PendingNoteOperationData(
            operationId: 'op2',
            noteId: 'n1',
            baseRevision: 10, // locally it had baseRevision 10 or 11
            ordinal: 1,
            kind: 'text_delta',
            blockId: 'b1',
            payloadJson: jsonEncode({
              'ops': [
                {'retain': 2},
                {'insert': 'X'},
              ],
            }),
            createdAt: DateTime.now(),
            status: 'pending',
            attemptCount: 0,
          ),
        ];

        final remote = [
          Operation(
            operationId: 'opR1',
            noteId: 'n1',
            revision: 11,
            baseRevision: 10,
            actorId: 'client2',
            kind: 'text_delta',
            blockId: 'b1',
            payload: {
              'ops': [
                {'retain': 1},
                {'insert': 'Y'},
              ],
            },
            createdAt: DateTime.now(),
          ),
        ];

        final result = rebaser.rebase(
          inFlight: inFlight,
          pending: pending,
          remote: remote,
          finalRevision:
              12, // After sync, final revision is 12 (opR1 and op1 both committed).
        );

        expect(result.length, 1);
        final rebasedPending = result.first;
        expect(rebasedPending.baseRevision, 12);

        final payload = jsonDecode(rebasedPending.payloadJson);
        final ops = payload['ops'] as List<dynamic>;

        // Remote R1 (insert 'Y' at 1) transforms against P1 (delete at 2).
        // Since they operate at different indices (1 vs 2), R1 becomes: retain 1, insert 'Y'.
        // But P2 operates at index 2 (after 'ab'). Since R1 inserted 'Y' at 1, the string 'ab' became 'aYb'.
        // So P2's insertion at index 2 should shift right by 1 -> retain 3, insert 'X'.

        expect(ops, [
          {'retain': 3},
          {'insert': 'X'},
        ]);
      },
    );

    test(
      'retry scenario: does not re-transform remote ops that happened AFTER the accepted in-flight op',
      () {
        final rebaser = NoteOperationRebaser(localActorId: 'client1');

        // Scenario: P1 is accepted with revision 11.
        // Another client submits R1 which gets revision 12.
        // The app crashes before local DB commits the sync result.
        // Now it retries. The server deduplicates P1, meaning it accepts it again but its effect is already in the document.
        // The server returns R1 (rev 12) as remote operations, and P1 as accepted (rev 11).
        // Since R1 (12) > P1 (11), R1 was authored AFTER P1. R1 already contains P1's shift!
        // So R1 MUST NOT be transformed against P1.

        final inFlight = [
          PendingNoteOperationData(
            operationId: 'op1',
            noteId: 'n1',
            baseRevision: 10,
            ordinal: 0,
            kind: 'text_delta',
            blockId: 'b1',
            payloadJson: jsonEncode({
              'ops': [
                {'retain': 2},
                {'delete': 1},
              ],
            }),
            createdAt: DateTime.now(),
            status: 'in_flight',
            attemptCount: 1,
          ),
        ];

        final pending = [
          PendingNoteOperationData(
            operationId: 'op2',
            noteId: 'n1',
            baseRevision: 10,
            ordinal: 1,
            kind: 'text_delta',
            blockId: 'b1',
            payloadJson: jsonEncode({
              'ops': [
                {'retain': 2},
                {'insert': 'X'},
              ],
            }),
            createdAt: DateTime.now(),
            status: 'pending',
            attemptCount: 0,
          ),
        ];

        final remote = [
          Operation(
            operationId: 'opR1',
            noteId: 'n1',
            revision: 12, // Came after P1
            baseRevision: 11,
            actorId: 'client2',
            kind: 'text_delta',
            blockId: 'b1',
            payload: {
              'ops': [
                {'retain': 1},
                {'insert': 'Y'},
              ],
            },
            createdAt: DateTime.now(),
          ),
        ];

        final List<AcceptedOperation> acceptedOps = [
          AcceptedOperation(
            operationId: 'op1',
            revision: 11, // P1 was accepted at 11
            kind: 'text_delta', // Added kind
          ),
        ];

        final result = rebaser.rebase(
          inFlight: inFlight,
          pending: pending,
          remote: remote,
          finalRevision: 12,
          acceptedOps: acceptedOps,
        );

        final rebasedPending = result.first;
        final payload = jsonDecode(rebasedPending.payloadJson);
        final ops = payload['ops'] as List<dynamic>;

        // If R1 was incorrectly transformed against P1, R1 would shift 'Y' to the left (or whatever).
        // Since R1 is NOT transformed against P1, R1 is just: retain 1, insert 'Y'.
        // P2 (insert X at 2) transforms against R1 (insert Y at 1).
        // P2's insertion shifts right by 1 -> retain 3, insert 'X'.

        expect(ops, [
          {'retain': 3},
          {'insert': 'X'},
        ]);
      },
    );

    test('priority test: local wins over remote at the same index', () {
      final rebaser = NoteOperationRebaser(
        localActorId: 'B',
      ); // Lexicographically higher than 'A'

      final pending = [
        PendingNoteOperationData(
          operationId: 'op1',
          noteId: 'n1',
          baseRevision: 10,
          ordinal: 0,
          kind: 'text_delta',
          blockId: 'b1',
          payloadJson: jsonEncode({
            'ops': [
              {'retain': 1},
              {'insert': 'LOCAL'},
            ],
          }),
          createdAt: DateTime.now(),
          status: 'pending',
          attemptCount: 0,
        ),
      ];

      final remote = [
        Operation(
          operationId: 'opR1',
          noteId: 'n1',
          revision: 11,
          baseRevision: 10,
          actorId: 'A', // Lexicographically lower than 'B'
          kind: 'text_delta',
          blockId: 'b1',
          payload: {
            'ops': [
              {'retain': 1},
              {'insert': 'REMOTE'},
            ],
          },
          createdAt: DateTime.now(),
        ),
      ];

      final result = rebaser.rebase(
        inFlight: [],
        pending: pending,
        remote: remote,
        finalRevision: 11,
      );

      final ops = jsonDecode(result.first.payloadJson)['ops'];

      // Local wins ('B:op1' > 'A:opR1').
      // When local wins, local inserts FIRST (so its index doesn't shift).
      // Remote will insert after.
      // Wait: we are transforming LOCAL (pending) against REMOTE (applied).
      // If local wins, its operation should come first in the text.
      // So remote's insertion should NOT push local's index to the right.
      // Therefore, local's insertion stays at retain: 1.
      expect(ops, [
        {'retain': 1},
        {'insert': 'LOCAL'},
      ]);
    });

    test('priority test: remote wins over local at the same index', () {
      final rebaser = NoteOperationRebaser(
        localActorId: 'A',
      ); // Lexicographically lower than 'B'

      final pending = [
        PendingNoteOperationData(
          operationId: 'op1',
          noteId: 'n1',
          baseRevision: 10,
          ordinal: 0,
          kind: 'text_delta',
          blockId: 'b1',
          payloadJson: jsonEncode({
            'ops': [
              {'retain': 1},
              {'insert': 'LOCAL'},
            ],
          }),
          createdAt: DateTime.now(),
          status: 'pending',
          attemptCount: 0,
        ),
      ];

      final remote = [
        Operation(
          operationId: 'opR1',
          noteId: 'n1',
          revision: 11,
          baseRevision: 10,
          actorId: 'B', // Lexicographically higher than 'A'
          kind: 'text_delta',
          blockId: 'b1',
          payload: {
            'ops': [
              {'retain': 1},
              {'insert': 'REMOTE'},
            ],
          },
          createdAt: DateTime.now(),
        ),
      ];

      final result = rebaser.rebase(
        inFlight: [],
        pending: pending,
        remote: remote,
        finalRevision: 11,
      );

      final ops = jsonDecode(result.first.payloadJson)['ops'];

      // Remote wins ('B:opR1' > 'A:op1').
      // When remote wins, remote inserts FIRST.
      // So local's insertion shifts right by remote's length ('REMOTE'.length == 6).
      // 1 (original retain) + 6 (remote insert length) = 7.
      expect(ops, [
        {'retain': 7},
        {'insert': 'LOCAL'},
      ]);
    });
  });
}
