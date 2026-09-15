import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/tasks/domain/task_operation.dart';

void main() {
  test('same payload has the same deterministic hash', () {
    final first = TaskOperation.upsert(
      taskId: 'task-1',
      payload: {'b': 2, 'a': 1},
    );
    final second = TaskOperation.upsert(
      taskId: 'task-1',
      payload: {'a': 1, 'b': 2},
    );
    expect(first.payloadHash, second.payloadHash);
  });

  test('changed payload has a different hash', () {
    final first = TaskOperation.upsert(
      taskId: 'task-1',
      payload: {'title': 'one'},
    );
    final second = TaskOperation.upsert(
      taskId: 'task-1',
      payload: {'title': 'two'},
    );
    expect(first.payloadHash, isNot(second.payloadHash));
  });

  test('snapshots payloads before exposing or hashing them', () {
    final payload = <String, dynamic>{
      'nested': <String, dynamic>{'value': 1},
    };
    final operation = TaskOperation.upsert(
      taskId: 'task-1',
      operationId: 'op-1',
      payload: payload,
    );
    payload['nested']['value'] = 2;
    expect(operation.payload['nested']['value'], 1);
    expect(operation.payloadHash, isNotEmpty);
  });

  test(
    'normalizes occurrence operations with the requested schedule identity',
    () {
      final allDay = TaskOperation.completeOccurrence(
        taskId: 'task-1',
        scheduledAt: '2026-09-15T09:00:00',
        hasTime: false,
        scheduleGeneration: 0,
      );
      final timed = TaskOperation.reopenOccurrence(
        taskId: 'task-1',
        scheduledAt: '2026-09-15T09:00:00',
        hasTime: true,
        scheduleGeneration: 0,
      );
      expect(allDay.payload['scheduledAt'], '2026-09-15T00:00:00.000');
      expect(timed.payload['scheduledAt'], '2026-09-15T09:00:00.000');
    },
  );
}
