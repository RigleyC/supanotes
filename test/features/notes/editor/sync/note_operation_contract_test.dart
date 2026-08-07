import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:supanotes/features/notes/editor/sync/note_operation_contract.dart';

void main() {
  Map<String, dynamic> loadFixture() =>
      jsonDecode(
            File('test/fixtures/operation_contract.json').readAsStringSync(),
          )
          as Map<String, dynamic>;

  test('shared fixture uses all known operation kinds and valid payloads', () {
    final fixture = loadFixture();
    final operations = fixture['operations'] as List<dynamic>;

    expect(operations, hasLength(NoteOperationKind.values.length));
    for (final rawOperation in operations) {
      final operation = rawOperation as Map<String, dynamic>;
      final payload = Map<String, dynamic>.from(operation['payload'] as Map);
      final kind = operation['kind'] as String;
      expect(NoteOperationKind.tryParse(kind), isNotNull);
      expect(
        NoteOperationContract.validate(
          kind: kind,
          blockId: operation['blockId'] as String?,
          payload: payload,
        ),
        isNull,
        reason: kind,
      );
    }
  });

  test('payload builders preserve the REST/OT wire shapes', () {
    expect(NoteOperationPayloads.deleteBlock('b1'), {'blockId': 'b1'});
    expect(NoteOperationPayloads.moveBlock(blockId: 'b1', afterBlockId: null), {
      'blockId': 'b1',
      'afterBlockId': null,
    });
    expect(
      NoteOperationPayloads.completeTaskOccurrence(
        taskId: 'task-1',
        scheduledAt: '2026-07-27T09:00:00Z',
        completedAt: null,
      ),
      {
        'taskId': 'task-1',
        'scheduledAt': '2026-07-27T09:00:00Z',
        'completedAt': null,
      },
    );
  });

  test('contract rejects a mismatched task occurrence payload', () {
    expect(
      NoteOperationContract.validate(
        kind: NoteOperationKind.completeTaskOccurrence.wireName,
        blockId: 'task-1',
        payload: const {
          'taskId': 'other-task',
          'scheduledAt': '2026-07-27T09:00:00Z',
          'completedAt': null,
        },
      ),
      isNotNull,
    );
  });

  test('contract accepts a create block without metadata', () {
    final error = NoteOperationContract.validate(
      kind: NoteOperationKind.createBlock.wireName,
      blockId: 'block-1',
      payload: {
        'id': 'block-1',
        'type': 'paragraph',
        'delta': [
          {'insert': 'text'},
        ],
        'metadata': null,
      },
    );

    expect(error, isNull);
  });
}
