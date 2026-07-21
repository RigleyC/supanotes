import 'dart:convert';

import 'package:dart_quill_delta/dart_quill_delta.dart' as quill;
import 'package:flutter_test/flutter_test.dart';

import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/features/notes/data/note_operations_api.dart';
import 'package:supanotes/features/notes/domain/note_operation_rebaser.dart';

void main() {
  group('transformTextPair', () {
    test('local wins when localKey > remoteKey', () {
      final result = transformTextPair(
        local: quill.Delta()..insert('Hello'),
        remote: quill.Delta()..insert('World'),
        localKey: 'b:1',
        remoteKey: 'a:1',
      );

      expect(result.local.toJson(), [
        {'insert': 'Hello'},
      ]);
    });

    test('remote wins when remoteKey > localKey', () {
      final result = transformTextPair(
        local: quill.Delta()..insert('Hello'),
        remote: quill.Delta()..insert('World'),
        localKey: 'a:1',
        remoteKey: 'b:1',
      );

      expect(result.remote.toJson(), [
        {'insert': 'World'},
      ]);
    });

    test('transforms concurrent insert at same position', () {
      final result = transformTextPair(
        local: quill.Delta()
          ..retain(5)
          ..insert(' AB'),
        remote: quill.Delta()
          ..retain(5)
          ..insert(' CD'),
        localKey: 'actor-1:op-1',
        remoteKey: 'actor-2:op-1',
      );

      expect(result.local.toJson(), [
        {'retain': 8},
        {'insert': ' AB'},
      ]);

      expect(result.remote.toJson(), [
        {'retain': 5},
        {'insert': ' CD'},
      ]);
    });
  });

  group('NoteOperationRebaser.rebase', () {
    late NoteOperationRebaser rebaser;

    setUp(() {
      rebaser = NoteOperationRebaser(localActorId: 'local-actor');
    });

    PendingNoteOperationData _pending({
      required String operationId,
      required String kind,
      String? blockId,
      Map<String, dynamic> payload = const {},
      int ordinal = 0,
      int baseRevision = 0,
    }) {
      return PendingNoteOperationData(
        operationId: operationId,
        noteId: 'note-1',
        baseRevision: baseRevision,
        ordinal: ordinal,
        kind: kind,
        blockId: blockId,
        payloadJson: jsonEncode(payload),
        createdAt: DateTime.utc(2026, 7, 20),
        attemptCount: 0,
        lastAttemptAt: null,
        status: 'pending',
      );
    }

    Operation _remote({
      required String operationId,
      required String kind,
      String actorId = 'remote-actor',
      String? blockId,
      Map<String, dynamic> payload = const {},
    }) {
      return Operation(
        operationId: operationId,
        noteId: 'note-1',
        revision: 1,
        baseRevision: 0,
        actorId: actorId,
        kind: kind,
        blockId: blockId,
        payload: payload,
        createdAt: DateTime.utc(2026, 7, 20),
      );
    }

    group('text_delta', () {
      test('transforms text_delta against remote text_delta on same block', () {
        final pending = [
          _pending(
            operationId: 'op-1',
            kind: 'text_delta',
            blockId: 'block-1',
            payload: {
              'ops': [
                {'retain': 5},
                {'insert': ' AB'},
              ],
            },
          ),
        ];
        final remote = [
          _remote(
            operationId: 'remote-1',
            kind: 'text_delta',
            blockId: 'block-1',
            payload: {
              'ops': [
                {'retain': 5},
                {'insert': ' CD'},
              ],
            },
          ),
        ];

        final result = rebaser.rebase(
          pending: pending,
          remote: remote,
          finalRevision: 10,
        );

        expect(result.length, 1);
        expect(result[0].baseRevision, 10);
        final decoded = jsonDecode(result[0].payloadJson) as Map<String, dynamic>;
        final ops = decoded['ops'] as List;
        expect(ops, [
          {'retain': 8},
          {'insert': ' AB'},
        ]);
      });

      test('transforms text_delta against remote text_delta on different blocks',
          () {
        final pending = [
          _pending(
            operationId: 'op-1',
            kind: 'text_delta',
            blockId: 'block-1',
            payload: {
              'ops': [
                {'retain': 5},
                {'insert': ' A'},
              ],
            },
          ),
        ];
        final remote = [
          _remote(
            operationId: 'remote-1',
            kind: 'text_delta',
            blockId: 'block-2',
            payload: {
              'ops': [
                {'retain': 3},
                {'insert': ' B'},
              ],
            },
          ),
        ];

        final result = rebaser.rebase(
          pending: pending,
          remote: remote,
          finalRevision: 5,
        );

        expect(result.length, 1);
        final decoded = jsonDecode(result[0].payloadJson) as Map<String, dynamic>;
        final ops = decoded['ops'] as List;
        expect(ops, [
          {'retain': 5},
          {'insert': ' A'},
        ]);
      });

      test('eliminates text_delta when remote deletes the block', () {
        final pending = [
          _pending(
            operationId: 'op-1',
            kind: 'text_delta',
            blockId: 'block-1',
            payload: {
              'ops': [
                {'retain': 5},
                {'insert': ' A'},
              ],
            },
          ),
        ];
        final remote = [
          _remote(
            operationId: 'remote-1',
            kind: 'delete_block',
            blockId: 'block-1',
            payload: {'blockId': 'block-1'},
          ),
        ];

        final result = rebaser.rebase(
          pending: pending,
          remote: remote,
          finalRevision: 3,
        );

        expect(result, isEmpty);
      });

      test('handles empty text_delta payload', () {
        final pending = [
          _pending(
            operationId: 'op-1',
            kind: 'text_delta',
            blockId: 'block-1',
            payload: {'title': 'untouched'},
          ),
        ];
        final remote = <Operation>[];

        final result = rebaser.rebase(
          pending: pending,
          remote: remote,
          finalRevision: 0,
        );

        expect(result.length, 1);
        final decoded = jsonDecode(result[0].payloadJson) as Map<String, dynamic>;
        expect(decoded['title'], 'untouched');
      });
    });

    group('block operations', () {
      group('create_block', () {
        test('adjusts afterBlockId when remote create_block targets same parent',
            () {
          final pending = [
            _pending(
              operationId: 'local-create',
              kind: 'create_block',
              blockId: 'new-block-a',
              payload: {
                'id': 'new-block-a',
                'type': 'paragraph',
                'afterBlockId': 'existing-block',
              },
            ),
          ];
          final remote = [
            _remote(
              operationId: 'remote-create',
              kind: 'create_block',
              blockId: 'new-block-b',
              payload: {
                'id': 'new-block-b',
                'type': 'paragraph',
                'afterBlockId': 'existing-block',
              },
            ),
          ];

          final result = rebaser.rebase(
            pending: pending,
            remote: remote,
            finalRevision: 1,
          );

          expect(result.length, 1);
          final decoded =
              jsonDecode(result[0].payloadJson) as Map<String, dynamic>;
          expect(decoded['afterBlockId'], 'new-block-b');
        });

        test('keeps afterBlockId when local has higher operationId', () {
          final pending = [
            _pending(
              operationId: 'z-local-create',
              kind: 'create_block',
              blockId: 'new-block-a',
              payload: {
                'id': 'new-block-a',
                'type': 'paragraph',
                'afterBlockId': 'existing-block',
              },
            ),
          ];
          final remote = [
            _remote(
              operationId: 'a-remote-create',
              kind: 'create_block',
              blockId: 'new-block-b',
              payload: {
                'id': 'new-block-b',
                'type': 'paragraph',
                'afterBlockId': 'existing-block',
              },
            ),
          ];

          final result = rebaser.rebase(
            pending: pending,
            remote: remote,
            finalRevision: 1,
          );

          expect(result.length, 1);
          final decoded =
              jsonDecode(result[0].payloadJson) as Map<String, dynamic>;
        expect(decoded['afterBlockId'], 'existing-block');
      });

      test('clears afterBlockId when remote deletes the target', () {
          final pending = [
            _pending(
              operationId: 'local-create',
              kind: 'create_block',
              blockId: 'new-block',
              payload: {
                'id': 'new-block',
                'type': 'paragraph',
                'afterBlockId': 'sibling-block',
              },
            ),
          ];
          final remote = [
            _remote(
              operationId: 'remote-del',
              kind: 'delete_block',
              blockId: 'sibling-block',
              payload: {'blockId': 'sibling-block'},
            ),
          ];

          final result = rebaser.rebase(
            pending: pending,
            remote: remote,
            finalRevision: 1,
          );

          expect(result.length, 1);
          final decoded =
              jsonDecode(result[0].payloadJson) as Map<String, dynamic>;
          expect(decoded['afterBlockId'], isNull);
        });
      });

      group('delete_block', () {
        test('eliminates delete_block when remote also deletes same block', () {
          final pending = [
            _pending(
              operationId: 'local-del',
              kind: 'delete_block',
              blockId: 'block-1',
              payload: {'blockId': 'block-1'},
            ),
          ];
          final remote = [
            _remote(
              operationId: 'remote-del',
              kind: 'delete_block',
              blockId: 'block-1',
              payload: {'blockId': 'block-1'},
            ),
          ];

          final result = rebaser.rebase(
            pending: pending,
            remote: remote,
            finalRevision: 1,
          );

          expect(result, isEmpty);
        });
      });

      group('move_block', () {
        test('eliminates when remote also moves same target with higher priority',
            () {
          final pending = [
            _pending(
              operationId: 'a-local',
              kind: 'move_block',
              blockId: 'block-1',
              payload: {
                'blockId': 'block-1',
                'afterBlockId': 'block-3',
              },
            ),
          ];
          final remote = [
            _remote(
              operationId: 'z-remote',
              kind: 'move_block',
              blockId: 'block-1',
              payload: {
                'blockId': 'block-1',
                'afterBlockId': 'block-2',
              },
            ),
          ];

          final result = rebaser.rebase(
            pending: pending,
            remote: remote,
            finalRevision: 1,
          );

          expect(result, isEmpty);
        });

        test('keeps move_block when local has higher priority', () {
          final pending = [
            _pending(
              operationId: 'z-local',
              kind: 'move_block',
              blockId: 'block-1',
              payload: {
                'blockId': 'block-1',
                'afterBlockId': 'block-3',
              },
            ),
          ];
          final remote = [
            _remote(
              operationId: 'a-remote',
              kind: 'move_block',
              blockId: 'block-1',
              payload: {
                'blockId': 'block-1',
                'afterBlockId': 'block-2',
              },
            ),
          ];

          final result = rebaser.rebase(
            pending: pending,
            remote: remote,
            finalRevision: 1,
          );

          expect(result.length, 1);
        });

        test('clears afterBlockId when remote deletes the target', () {
          final pending = [
            _pending(
              operationId: 'local-move',
              kind: 'move_block',
              blockId: 'block-1',
              payload: {
                'blockId': 'block-1',
                'afterBlockId': 'sibling-block',
              },
            ),
          ];
          final remote = [
            _remote(
              operationId: 'remote-del',
              kind: 'delete_block',
              blockId: 'sibling-block',
              payload: {'blockId': 'sibling-block'},
            ),
          ];

          final result = rebaser.rebase(
            pending: pending,
            remote: remote,
            finalRevision: 1,
          );

          expect(result.length, 1);
          final decoded =
              jsonDecode(result[0].payloadJson) as Map<String, dynamic>;
          expect(decoded['afterBlockId'], isNull);
        });

        test('eliminates when remote deletes the moved block', () {
          final pending = [
            _pending(
              operationId: 'local-move',
              kind: 'move_block',
              blockId: 'block-1',
              payload: {
                'blockId': 'block-1',
                'afterBlockId': 'block-2',
              },
            ),
          ];
          final remote = [
            _remote(
              operationId: 'remote-del',
              kind: 'delete_block',
              blockId: 'block-1',
              payload: {'blockId': 'block-1'},
            ),
          ];

          final result = rebaser.rebase(
            pending: pending,
            remote: remote,
            finalRevision: 1,
          );

          expect(result, isEmpty);
        });
      });

      group('set_block_type', () {
        test('eliminates when remote deletes the block', () {
          final pending = [
            _pending(
              operationId: 'local-set',
              kind: 'set_block_type',
              blockId: 'block-1',
              payload: {'type': 'header1'},
            ),
          ];
          final remote = [
            _remote(
              operationId: 'remote-del',
              kind: 'delete_block',
              blockId: 'block-1',
              payload: {'blockId': 'block-1'},
            ),
          ];

          final result = rebaser.rebase(
            pending: pending,
            remote: remote,
            finalRevision: 1,
          );

          expect(result, isEmpty);
        });
      });
    });

    group('baseRevision assignment', () {
      test('assigns sequential baseRevisions starting from finalRevision', () {
        final pending = [
          _pending(
            operationId: 'op-1',
            kind: 'create_block',
            blockId: 'b1',
            payload: {'id': 'b1', 'type': 'paragraph'},
          ),
          _pending(
            operationId: 'op-2',
            kind: 'text_delta',
            blockId: 'b1',
            payload: {'ops': [{'insert': 'Hello'}]},
          ),
          _pending(
            operationId: 'op-3',
            kind: 'create_block',
            blockId: 'b2',
            payload: {'id': 'b2', 'type': 'paragraph'},
          ),
        ];

        final result = rebaser.rebase(
          pending: pending,
          remote: [],
          finalRevision: 7,
        );

        expect(result.length, 3);
        expect(result[0].baseRevision, 7);
        expect(result[1].baseRevision, 8);
        expect(result[2].baseRevision, 9);
      });

      test('assigns sequential after eliminating no-ops', () {
        final pending = [
          _pending(
            operationId: 'op-1',
            kind: 'delete_block',
            blockId: 'b1',
            payload: {'blockId': 'b1'},
          ),
          _pending(
            operationId: 'op-2',
            kind: 'create_block',
            blockId: 'b2',
            payload: {'id': 'b2', 'type': 'paragraph'},
          ),
        ];
        final remote = [
          _remote(
            operationId: 'remote-del',
            kind: 'delete_block',
            blockId: 'b1',
            payload: {'blockId': 'b1'},
          ),
        ];

        final result = rebaser.rebase(
          pending: pending,
          remote: remote,
          finalRevision: 5,
        );

        expect(result.length, 1);
        expect(result[0].baseRevision, 5);
        expect(result[0].operationId, 'op-2');
      });
    });

    group('mixed operations', () {
      test('transforms text_delta and block ops together', () {
        final pending = [
          _pending(
            operationId: 'op-1',
            kind: 'create_block',
            blockId: 'b2',
            payload: {'id': 'b2', 'type': 'paragraph', 'afterBlockId': 'b1'},
          ),
          _pending(
            operationId: 'op-2',
            kind: 'text_delta',
            blockId: 'b2',
            payload: {
              'ops': [
                {'insert': 'Hello'},
              ],
            },
          ),
        ];
        final remote = [
          _remote(
            operationId: 'remote-create',
            kind: 'create_block',
            blockId: 'b1',
            payload: {
              'id': 'b1',
              'type': 'paragraph',
              'afterBlockId': null,
            },
          ),
        ];

        final result = rebaser.rebase(
          pending: pending,
          remote: remote,
          finalRevision: 3,
        );

        expect(result.length, 2);
        expect(result[0].baseRevision, 3);
        expect(result[1].baseRevision, 4);
      });

      test('returns empty when all ops eliminated', () {
        final pending = [
          _pending(
            operationId: 'op-1',
            kind: 'delete_block',
            blockId: 'b1',
            payload: {'blockId': 'b1'},
          ),
        ];
        final remote = [
          _remote(
            operationId: 'remote-del',
            kind: 'delete_block',
            blockId: 'b1',
            payload: {'blockId': 'b1'},
          ),
        ];

        final result = rebaser.rebase(
          pending: pending,
          remote: remote,
          finalRevision: 0,
        );

        expect(result, isEmpty);
      });
    });
  });
}
