import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/tasks/domain/task_occurrence.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';

void main() {
  final now = DateTime(2026, 7, 21, 10);

  group('current occurrence - non-recurring', () {
    test('returns single pending occurrence when dueDate is in future', () {
      final result = _currentOccurrence(
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
      final result = _currentOccurrence(
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
      final result = _currentOccurrence(
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
      final result = _currentOccurrence(
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

  group('current occurrence - daily recurrence', () {
    test('advances missed occurrences to the current day', () {
      final result = _currentOccurrence(
        taskId: 't1',
        anchor: DateTime(2026, 7),
        recurrence: TaskRecurrence.daily,
        hasTime: false,
        now: now,
        completedScheduledAts: {},
      );

      expect(result, hasLength(1));
      expect(result.single.scheduledAt, DateTime(2026, 7, 21));
      expect(result.single.status, OccurrenceStatus.pending);
    });

    test('does not keep missed completion history as overdue occurrences', () {
      final result = _currentOccurrence(
        taskId: 't1',
        anchor: DateTime(2026, 7),
        recurrence: TaskRecurrence.daily,
        hasTime: false,
        now: now,
        completedScheduledAts: {DateTime(2026, 7), DateTime(2026, 7, 2)},
      );

      expect(result, hasLength(1));
      expect(result.single.scheduledAt, DateTime(2026, 7, 21));
      expect(result.single.status, OccurrenceStatus.pending);
    });

    test('keeps the current occurrence completed after early completion', () {
      final currentOccurrence = DateTime(2026, 7, 21);
      final result = _currentOccurrence(
        taskId: 't1',
        anchor: DateTime(2026, 7),
        recurrence: TaskRecurrence.daily,
        hasTime: false,
        now: DateTime(2026, 7, 21, 10),
        completedScheduledAts: {currentOccurrence},
      );

      expect(result, hasLength(1));
      expect(result.single.scheduledAt, currentOccurrence);
      expect(result.single.status, OccurrenceStatus.completed);
    });

    test('respects hasTime in date comparison', () {
      final result = _currentOccurrence(
        taskId: 't1',
        anchor: DateTime(2026, 7, 21, 14),
        recurrence: TaskRecurrence.daily,
        hasTime: true,
        now: DateTime(2026, 7, 21, 10),
        completedScheduledAts: {},
      );

      final today = result.firstWhere(
        (o) =>
            o.scheduledAt.year == 2026 &&
            o.scheduledAt.month == 7 &&
            o.scheduledAt.day == 21,
      );
      expect(today.status, OccurrenceStatus.pending);
      expect(today.scheduledAt.hour, 14);
    });
  });

  group('current occurrence - weekly recurrence', () {
    test('keeps only the latest reached occurrence', () {
      final result = _currentOccurrence(
        taskId: 't1',
        anchor: DateTime(2026, 7),
        recurrence: TaskRecurrence.weekly,
        hasTime: false,
        now: now,
        completedScheduledAts: {},
      );

      expect(result, hasLength(1));
      expect(result.single.scheduledAt, DateTime(2026, 7, 15));
      expect(result.single.status, OccurrenceStatus.overdue);
    });

    test('does not show earlier missed weeks when the current week starts', () {
      final result = _currentOccurrence(
        taskId: 't1',
        anchor: DateTime(2026, 7, 7),
        recurrence: TaskRecurrence.weekly,
        hasTime: false,
        now: DateTime(2026, 7, 21),
        completedScheduledAts: {DateTime(2026, 7, 7)},
      );

      expect(result, hasLength(1));
      expect(result.single.scheduledAt, DateTime(2026, 7, 21));
      expect(result.single.status, OccurrenceStatus.pending);
    });

    test(
      'a completion from a missed week does not reopen an old occurrence',
      () {
        final result = _currentOccurrence(
          taskId: 't1',
          anchor: DateTime(2026, 7, 7),
          recurrence: TaskRecurrence.weekly,
          hasTime: false,
          now: DateTime(2026, 7, 21),
          completedScheduledAts: {DateTime(2026, 7, 14)},
        );

        expect(result, hasLength(1));
        expect(result.single.scheduledAt, DateTime(2026, 7, 21));
        expect(result.single.status, OccurrenceStatus.pending);
      },
    );
  });

  group('current occurrence - monthly recurrence', () {
    test('advances to the latest reached month', () {
      final result = _currentOccurrence(
        taskId: 't1',
        anchor: DateTime(2026, 1, 15),
        recurrence: TaskRecurrence.monthly,
        hasTime: false,
        now: DateTime(2026, 4),
        completedScheduledAts: {},
      );

      expect(result, hasLength(1));
      expect(result.single.scheduledAt, DateTime(2026, 3, 15));
      expect(result.single.status, OccurrenceStatus.overdue);
    });

    test('clamps day for month with fewer days', () {
      final result = _currentOccurrence(
        taskId: 't1',
        anchor: DateTime(2026, 1, 31),
        recurrence: TaskRecurrence.monthly,
        hasTime: false,
        now: DateTime(2026, 3),
        completedScheduledAts: {},
      );

      expect(result, hasLength(1));
      expect(result.single.scheduledAt, DateTime(2026, 2, 28));
    });

    test('returns to the anchor day after a short month', () {
      final result = _currentOccurrence(
        taskId: 't1',
        anchor: DateTime(2026, 1, 31),
        recurrence: TaskRecurrence.monthly,
        hasTime: false,
        now: DateTime(2026, 3, 31),
        completedScheduledAts: {DateTime(2026, 2, 28)},
      );

      expect(result.single.scheduledAt, DateTime(2026, 3, 31));
      expect(result.single.status, OccurrenceStatus.pending);
    });

    test('keeps the first not-yet-started completed occurrence current', () {
      final result = _currentOccurrence(
        taskId: 't1',
        anchor: DateTime(2026, 8, 12),
        recurrence: TaskRecurrence.weekly,
        hasTime: false,
        now: DateTime(2026, 8, 10, 10),
        completedScheduledAts: {DateTime(2026, 8, 12), DateTime(2026, 8, 19)},
      );

      expect(result.single.scheduledAt, DateTime(2026, 8, 12));
      expect(result.single.status, OccurrenceStatus.completed);
    });

    test('keeps an overdue occurrence until the next date starts', () {
      final beforeNext = _currentOccurrence(
        taskId: 't1',
        anchor: DateTime(2026, 8, 12),
        recurrence: TaskRecurrence.weekly,
        hasTime: false,
        now: DateTime(2026, 8, 18),
        completedScheduledAts: {},
      );
      final atNext = _currentOccurrence(
        taskId: 't1',
        anchor: DateTime(2026, 8, 12),
        recurrence: TaskRecurrence.weekly,
        hasTime: false,
        now: DateTime(2026, 8, 19),
        completedScheduledAts: {},
      );

      expect(beforeNext.single.scheduledAt, DateTime(2026, 8, 12));
      expect(beforeNext.single.status, OccurrenceStatus.overdue);
      expect(atNext.single.scheduledAt, DateTime(2026, 8, 19));
      expect(atNext.single.status, OccurrenceStatus.pending);
    });
  });

  group('current occurrence - weekdays recurrence', () {
    test('skips weekends', () {
      final result = _currentOccurrence(
        taskId: 't1',
        anchor: DateTime(2026, 7),
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

  group('current occurrence - edge cases', () {
    test('preserves time of day', () {
      final result = _currentOccurrence(
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

    test('same date is pending not overdue', () {
      final result = _currentOccurrence(
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

/// The occurrence the task list shows for a task, as a 0- or 1-item list.
List<TaskOccurrence> _currentOccurrence({
  required String taskId,
  required DateTime? anchor,
  required TaskRecurrence? recurrence,
  required bool hasTime,
  required DateTime now,
  required Set<DateTime> completedScheduledAts,
}) {
  final occurrence = TaskOccurrencePolicy(clock: () => now).resolveCurrent(
    taskId: taskId,
    anchor: anchor,
    recurrence: recurrence,
    hasTime: hasTime,
    completedAtByScheduledAt: {
      for (final scheduledAt in completedScheduledAts) scheduledAt: scheduledAt,
    },
  );
  return occurrence == null ? [] : [occurrence];
}
