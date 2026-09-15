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
}
