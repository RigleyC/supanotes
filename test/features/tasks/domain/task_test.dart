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

  test(
    'preserves scheduled wall-clock values while UTC normalizes instants',
    () {
      final task = fixtureRecurringTask();
      final json = task.toJson();
      expect(json['due_date'], '2026-09-15T09:00:00.000');
      expect(Task.fromJson(json).dueDate, task.dueDate);
    },
  );

  test('copyWith can clear nullable schedule metadata', () {
    final task = fixtureRecurringTask().copyWith(
      dueDate: null,
      recurrenceRule: null,
      reminder: null,
    );
    expect(task.dueDate, isNull);
    expect(task.recurrenceRule, isNull);
    expect(task.reminder, isNull);
  });

  test('canonicalizes equivalent completion representations', () {
    final first = fixtureRecurringTask(
      completions: {
        '2026-09-15T09:00': '2026-09-14T09:00:00.000Z',
      },
    );
    final second = fixtureRecurringTask(
      completions: {
        '2026-09-15T09:00:00.000': '2026-09-14T09:00:00Z',
      },
    );
    expect(first.completions, second.completions);
  });

  test('rejects invalid completion representations', () {
    expect(
      () => fixtureRecurringTask(
        completions: {'not-a-date': '2026-09-14T12:00:00Z'},
      ),
      throwsFormatException,
    );
  });

  test('canonicalizes all-day completion keys without retaining a time', () {
    final task = Task(
      id: 'task-1',
      ownerUserId: 'user-1',
      title: 'All day',
      hasTime: false,
      completions: {
        '2026-09-15T09:00:00': '2026-09-14T12:00:00Z',
      },
      createdAt: DateTime.utc(2026, 9, 1),
      updatedAt: DateTime.utc(2026, 9, 14),
    );
    expect(task.completions.keys, contains('2026-09-15T00:00:00.000'));
  });

  test('withSchedule preserves omitted nullable fields', () {
    final task = fixtureRecurringTask();
    final changed = task.withSchedule(hasTime: false);
    expect(changed.dueDate, isNotNull);
    expect(changed.dueDate!.year, task.dueDate!.year);
    expect(changed.dueDate!.month, task.dueDate!.month);
    expect(changed.dueDate!.day, task.dueDate!.day);
    expect(changed.recurrenceRule, task.recurrenceRule);
  });

  test('withSchedule supports explicit nullable field clearing', () {
    final task = fixtureRecurringTask();
    final changed = task.withSchedule(dueDate: null, recurrenceRule: null);
    expect(changed.dueDate, isNull);
    expect(changed.recurrenceRule, isNull);
  });

  test('rejects scheduled offsets instead of shifting wall-clock identity', () {
    final json = fixtureRecurringTask().toJson();
    json['due_date'] = '2026-09-15T09:00:00-03:00';
    expect(() => Task.fromJson(json), throwsFormatException);
  });

  test('validates generation and instant wire formats strictly', () {
    final decimal = fixtureRecurringTask().toJson()
      ..['schedule_generation'] = 1.5;
    expect(() => Task.fromJson(decimal), throwsFormatException);
    final negative = fixtureRecurringTask().toJson()
      ..['schedule_generation'] = -1;
    expect(() => Task.fromJson(negative), throwsFormatException);
    final string = fixtureRecurringTask().toJson()
      ..['schedule_generation'] = '1';
    expect(() => Task.fromJson(string), throwsFormatException);
    final localInstant = fixtureRecurringTask().toJson()
      ..['created_at'] = '2026-09-01T00:00:00.000';
    expect(() => Task.fromJson(localInstant), throwsFormatException);
  });
}
