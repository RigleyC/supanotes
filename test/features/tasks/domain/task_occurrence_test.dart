import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/tasks/domain/task_occurrence.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';

void main() {
  final now = DateTime(2026, 7, 21, 10, 0);

  group('buildOccurrences - non-recurring', () {
    test('returns single pending occurrence when dueDate is in future', () {
      final result = buildOccurrences(
        taskId: 't1',
        anchor: DateTime(2026, 7, 25),
        recurrence: null,
        hasTime: false,
        now: now,
        completedScheduledAts: {},
      );

      expect(result, hasLength(1));
      expect(result[0].status, OccurrenceStatus.pending);
      expect(result[0].scheduledAt, DateTime(2026, 7, 25));
    });

    test('returns single overdue occurrence when dueDate is past', () {
      final result = buildOccurrences(
        taskId: 't1',
        anchor: DateTime(2026, 7, 15),
        recurrence: null,
        hasTime: false,
        now: now,
        completedScheduledAts: {},
      );

      expect(result, hasLength(1));
      expect(result[0].status, OccurrenceStatus.overdue);
    });

    test('returns completed occurrence when anchor matches a completion', () {
      final result = buildOccurrences(
        taskId: 't1',
        anchor: DateTime(2026, 7, 15),
        recurrence: null,
        hasTime: false,
        now: now,
        completedScheduledAts: {DateTime(2026, 7, 15)},
      );

      expect(result, hasLength(1));
      expect(result[0].status, OccurrenceStatus.completed);
    });

    test('returns empty when anchor is null', () {
      final result = buildOccurrences(
        taskId: 't1',
        anchor: null,
        recurrence: TaskRecurrence.daily,
        hasTime: false,
        now: now,
        completedScheduledAts: {},
      );

      expect(result, isEmpty);
    });
  });

  group('buildOccurrences - daily recurrence', () {
    test('enumerates all occurrences from anchor to 30 days ahead', () {
      final result = buildOccurrences(
        taskId: 't1',
        anchor: DateTime(2026, 7, 1),
        recurrence: TaskRecurrence.daily,
        hasTime: false,
        now: now,
        completedScheduledAts: {},
      );

      expect(result.length, greaterThan(20));
      expect(result[0].scheduledAt, DateTime(2026, 7, 1));
      expect(result[0].status, OccurrenceStatus.overdue);
      expect(result[20].status, OccurrenceStatus.pending);
    });

    test('marks completed occurrences', () {
      final result = buildOccurrences(
        taskId: 't1',
        anchor: DateTime(2026, 7, 1),
        recurrence: TaskRecurrence.daily,
        hasTime: false,
        now: now,
        completedScheduledAts: {DateTime(2026, 7, 1), DateTime(2026, 7, 2)},
      );

      expect(result[0].status, OccurrenceStatus.completed);
      expect(result[1].status, OccurrenceStatus.completed);
      expect(result[2].status, OccurrenceStatus.overdue);
    });

    test('respects hasTime in date comparison', () {
      final result = buildOccurrences(
        taskId: 't1',
        anchor: DateTime(2026, 7, 21, 14, 0),
        recurrence: TaskRecurrence.daily,
        hasTime: true,
        now: DateTime(2026, 7, 21, 10, 0),
        completedScheduledAts: {},
      );

      final today = result.firstWhere((o) =>
          o.scheduledAt.year == 2026 &&
          o.scheduledAt.month == 7 &&
          o.scheduledAt.day == 21);
      expect(today.status, OccurrenceStatus.pending);
      expect(today.scheduledAt.hour, 14);
    });
  });

  group('buildOccurrences - weekly recurrence', () {
    test('marks missed weeks as overdue', () {
      final result = buildOccurrences(
        taskId: 't1',
        anchor: DateTime(2026, 7, 1),
        recurrence: TaskRecurrence.weekly,
        hasTime: false,
        now: now,
        completedScheduledAts: {},
      );

      expect(result[0].scheduledAt, DateTime(2026, 7, 1));
      expect(result[0].status, OccurrenceStatus.overdue);
      final nextIndex = result.indexWhere(
        (o) => o.status == OccurrenceStatus.pending,
      );
      expect(nextIndex, greaterThan(0));
    });

    test(
      'conclude 07/jul, not 14/jul, opens in 21/jul — 14/jul overdue, 21/jul pending',
      () {
        final result = buildOccurrences(
          taskId: 't1',
          anchor: DateTime(2026, 7, 7),
          recurrence: TaskRecurrence.weekly,
          hasTime: false,
          now: DateTime(2026, 7, 21),
          completedScheduledAts: {DateTime(2026, 7, 7)},
        );

        expect(result[0].scheduledAt, DateTime(2026, 7, 7));
        expect(result[0].status, OccurrenceStatus.completed);
        expect(result[1].scheduledAt, DateTime(2026, 7, 14));
        expect(result[1].status, OccurrenceStatus.overdue);
        expect(result[2].scheduledAt, DateTime(2026, 7, 21));
        expect(result[2].status, OccurrenceStatus.pending);
      },
    );

    test('completing an overdue occurrence does not affect current', () {
      final result = buildOccurrences(
        taskId: 't1',
        anchor: DateTime(2026, 7, 7),
        recurrence: TaskRecurrence.weekly,
        hasTime: false,
        now: DateTime(2026, 7, 21),
        completedScheduledAts: {DateTime(2026, 7, 14)},
      );

      expect(result[0].status, OccurrenceStatus.overdue);
      expect(result[1].scheduledAt, DateTime(2026, 7, 14));
      expect(result[1].status, OccurrenceStatus.completed);
      expect(result[2].status, OccurrenceStatus.pending);
    });
  });

  group('buildOccurrences - monthly recurrence', () {
    test('enumerates monthly occurrences', () {
      final result = buildOccurrences(
        taskId: 't1',
        anchor: DateTime(2026, 1, 15),
        recurrence: TaskRecurrence.monthly,
        hasTime: false,
        now: DateTime(2026, 4, 1),
        completedScheduledAts: {},
      );

      expect(result.length, greaterThanOrEqualTo(3));
      expect(result[0].scheduledAt, DateTime(2026, 1, 15));
      expect(result[0].status, OccurrenceStatus.overdue);
    });

    test('clamps day for month with fewer days', () {
      final result = buildOccurrences(
        taskId: 't1',
        anchor: DateTime(2026, 1, 31),
        recurrence: TaskRecurrence.monthly,
        hasTime: false,
        now: DateTime(2026, 3, 1),
        completedScheduledAts: {},
      );

      expect(result[0],
          predicate((TaskOccurrence o) => o.scheduledAt == DateTime(2026, 1, 31)));
      expect(result[1],
          predicate((TaskOccurrence o) => o.scheduledAt == DateTime(2026, 2, 28)));
    });
  });

  group('buildOccurrences - weekdays recurrence', () {
    test('skips weekends', () {
      final result = buildOccurrences(
        taskId: 't1',
        anchor: DateTime(2026, 7, 1),
        recurrence: TaskRecurrence.weekdays,
        hasTime: false,
        now: DateTime(2026, 7, 6),
        completedScheduledAts: {},
      );

      for (final o in result) {
        expect(
          o.scheduledAt.weekday,
          isNot(anyOf(DateTime.saturday, DateTime.sunday)),
        );
      }
    });
  });

  group('buildOccurrences - edge cases', () {
    test('preserves time of day', () {
      final result = buildOccurrences(
        taskId: 't1',
        anchor: DateTime(2026, 7, 21, 14, 30),
        recurrence: TaskRecurrence.daily,
        hasTime: true,
        now: now,
        completedScheduledAts: {},
      );

      for (final o in result) {
        expect(o.scheduledAt.hour, 14);
        expect(o.scheduledAt.minute, 30);
      }
    });

    test('limits total occurrences by maxCount', () {
      final result = buildOccurrences(
        taskId: 't1',
        anchor: DateTime(2026, 1, 1),
        recurrence: TaskRecurrence.daily,
        hasTime: false,
        now: now,
        completedScheduledAts: {},
        maxCount: 10,
      );

      expect(result.length, lessThanOrEqualTo(10));
    });

    test('same date is pending not overdue', () {
      final result = buildOccurrences(
        taskId: 't1',
        anchor: now,
        recurrence: null,
        hasTime: false,
        now: now,
        completedScheduledAts: {},
      );

      expect(result[0].status, OccurrenceStatus.pending);
    });
  });
}
