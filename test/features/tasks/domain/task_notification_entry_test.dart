import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/tasks/domain/task_notification_entry.dart';

void main() {
  test('compares equivalent scheduled wall-clock representations equally', () {
    final local = TaskNotificationEntry(
      id: 'task-1',
      title: 'All-day task',
      dueDate: DateTime(2026, 8, 12),
      hasTime: false,
      reminder: '9am',
    );
    final utc = TaskNotificationEntry(
      id: 'task-1',
      title: 'All-day task',
      dueDate: DateTime.utc(2026, 8, 12, 3),
      hasTime: false,
      reminder: '9am',
    );

    expect(local, utc);
    expect(local.hashCode, utc.hashCode);
  });

  test('does not merge different scheduled dates', () {
    final first = TaskNotificationEntry(
      id: 'task-1',
      title: 'Task',
      dueDate: DateTime(2026, 8, 12),
      hasTime: false,
      reminder: '9am',
    );
    final second = TaskNotificationEntry(
      id: 'task-1',
      title: 'Task',
      dueDate: DateTime(2026, 8, 13),
      hasTime: false,
      reminder: '9am',
    );

    expect(first, isNot(second));
  });
}
