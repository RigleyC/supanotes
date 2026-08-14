import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/tasks/domain/task_notification_time.dart';

void main() {
  final due = DateTime(2026, 8, 12, 14, 30);

  test('uses the task time for at-time reminders', () {
    expect(
      computeTaskNotificationTime(due: due, hasTime: true, reminder: 'at_time'),
      due,
    );
  });

  test('uses 9am as the base for an all-day at-time reminder', () {
    expect(
      computeTaskNotificationTime(
        due: DateTime(2026, 8, 12),
        hasTime: false,
        reminder: 'at_time',
      ),
      DateTime(2026, 8, 12, 9),
    );
  });

  test('keeps relative and absolute reminder options', () {
    expect(
      computeTaskNotificationTime(
        due: due,
        hasTime: true,
        reminder: '5m_before',
      ),
      DateTime(2026, 8, 12, 14, 25),
    );
    expect(
      computeTaskNotificationTime(
        due: due,
        hasTime: true,
        reminder: '1d_before_9am',
      ),
      DateTime(2026, 8, 11, 9),
    );
    expect(
      computeTaskNotificationTime(due: due, hasTime: false, reminder: '6pm'),
      DateTime(2026, 8, 12, 18),
    );
  });

  test('returns null when a task has no reminder', () {
    expect(
      computeTaskNotificationTime(due: due, hasTime: true, reminder: null),
      isNull,
    );
  });
}
