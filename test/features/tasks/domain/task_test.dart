import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/tasks/domain/task.dart';

Task fixtureRecurringTask({Map<String, Object?> completions = const {}}) =>
    Task(
      id: 'task-1',
      ownerUserId: 'user-1',
      title: 'Review',
      dueDate: DateTime.utc(2026, 9, 15, 9),
      hasTime: true,
      recurrenceRule: 'daily',
      completions: completions,
      createdAt: DateTime.utc(2026, 9, 1),
      updatedAt: DateTime.utc(2026, 9, 14),
    );

void main() {
  test('round trips a standalone task without losing completions', () {
    final task = fixtureRecurringTask(
      completions: {
        '2026-09-15T09:00:00.000': '2026-09-14T12:00:00.000Z',
      },
    );
    expect(Task.fromJson(task.toJson()), task);
  });

  test('schedule metadata changes clear history and increment generation', () {
    final task = fixtureRecurringTask(
      completions: {
        '2026-09-15T09:00:00.000': '2026-09-14T12:00:00.000Z',
      },
    );
    final changed = task.withSchedule(
      dueDate: DateTime.utc(2026, 9, 16, 9),
      hasTime: true,
      recurrenceRule: 'weekly',
    );
    expect(changed.scheduleGeneration, task.scheduleGeneration + 1);
    expect(changed.completions, isEmpty);
  });
}
