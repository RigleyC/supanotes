import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/tasks/domain/task_notification_id.dart';

void main() {
  final scheduledAt = DateTime(2026, 9, 15, 9);

  test('keeps equal IDs from standalone and note sources distinct', () {
    final standalone = TaskNotificationId.forTask(
      userId: 'user-1',
      taskId: 'same-id',
      scheduledAt: scheduledAt,
    );
    final note = TaskNotificationId.forNote(
      userId: 'user-1',
      noteId: 'note-1',
      blockId: 'same-id',
      scheduledAt: scheduledAt,
    );

    expect(standalone, isNot(note));
  });

  test('includes the scheduled occurrence in the ID', () {
    final first = TaskNotificationId.forTask(
      userId: 'user-1',
      taskId: 'task-1',
      scheduledAt: scheduledAt,
    );
    final nextOccurrence = TaskNotificationId.forTask(
      userId: 'user-1',
      taskId: 'task-1',
      scheduledAt: scheduledAt.add(const Duration(days: 1)),
    );

    expect(first, isNot(nextOccurrence));
  });

  test('legacy ID is different so migration can cancel it first', () {
    final legacy = TaskNotificationId.legacyForTask('user-1', 'task-1');
    final current = TaskNotificationId.forTask(
      userId: 'user-1',
      taskId: 'task-1',
      scheduledAt: scheduledAt,
    );

    expect(current, isNot(legacy));
  });
}
