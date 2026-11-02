import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/core/utils/recurrence.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';

void main() {
  group('enumerateOccurrences', () {
    test('returns empty list when anchor is null', () {
      final result = enumerateOccurrences(
        anchor: null,
        recurrence: TaskRecurrence.daily,
        from: DateTime(2026, 7),
        to: DateTime(2026, 7, 10),
      );
      expect(result, isEmpty);
    });

    test('returns empty list when recurrence is null', () {
      final result = enumerateOccurrences(
        anchor: DateTime(2026, 7),
        recurrence: null,
        from: DateTime(2026, 7),
        to: DateTime(2026, 7, 10),
      );
      expect(result, isEmpty);
    });

    test('daily: enumerates all days in range', () {
      final result = enumerateOccurrences(
        anchor: DateTime(2026, 7),
        recurrence: TaskRecurrence.daily,
        from: DateTime(2026, 7),
        to: DateTime(2026, 7, 5),
      );
      expect(result, hasLength(5));
      expect(result[0], DateTime(2026, 7));
      expect(result[4], DateTime(2026, 7, 5));
    });

    test('daily: starts from anchor even if anchor is before from', () {
      final result = enumerateOccurrences(
        anchor: DateTime(2026, 6, 28),
        recurrence: TaskRecurrence.daily,
        from: DateTime(2026, 7),
        to: DateTime(2026, 7, 3),
      );
      expect(result, hasLength(3));
      expect(result[0], DateTime(2026, 7));
      expect(result[2], DateTime(2026, 7, 3));
    });

    test('weekdays: skips weekends', () {
      // 2026-07-01 is a Wednesday
      final result = enumerateOccurrences(
        anchor: DateTime(2026, 7),
        recurrence: TaskRecurrence.weekdays,
        from: DateTime(2026, 7),
        to: DateTime(2026, 7, 6), // Monday
      );
      // July 1 (Wed), 2 (Thu), 3 (Fri), 6 (Mon) — Jul 4-5 are Sat-Sun
      expect(result, hasLength(4));
      expect(
        result.map((d) => d.weekday),
        everyElement(isNot(anyOf(DateTime.saturday, DateTime.sunday))),
      );
    });

    test('weekly: enumerates weekly', () {
      final result = enumerateOccurrences(
        anchor: DateTime(2026, 7),
        recurrence: TaskRecurrence.weekly,
        from: DateTime(2026, 7),
        to: DateTime(2026, 7, 22),
      );
      // Jul 1, 8, 15, 22
      expect(result, hasLength(4));
      expect(result[0], DateTime(2026, 7));
      expect(result[3], DateTime(2026, 7, 22));
    });

    test('monthly: enumerates monthly', () {
      final result = enumerateOccurrences(
        anchor: DateTime(2026, 1, 15),
        recurrence: TaskRecurrence.monthly,
        from: DateTime(2026, 1, 15),
        to: DateTime(2026, 4, 15),
      );
      expect(result, hasLength(4));
      expect(result[0], DateTime(2026, 1, 15));
      expect(result[3], DateTime(2026, 4, 15));
    });

    test(
      'monthly: clamps day for month with fewer days (Jan 31 -> Feb 28)',
      () {
        final result = enumerateOccurrences(
          anchor: DateTime(2026, 1, 31),
          recurrence: TaskRecurrence.monthly,
          from: DateTime(2026, 1, 31),
          to: DateTime(2026, 3, 31),
        );
        // Jan 31, Feb 28 (clamped), Mar 31 (original anchor day restored)
        expect(result, hasLength(3));
        expect(result[0], DateTime(2026, 1, 31));
        expect(result[1], DateTime(2026, 2, 28));
        expect(result[2], DateTime(2026, 3, 31));
      },
    );

    test('preserves time of day', () {
      final result = enumerateOccurrences(
        anchor: DateTime(2026, 7, 1, 14, 30),
        recurrence: TaskRecurrence.daily,
        from: DateTime(2026, 7),
        to: DateTime(2026, 7, 3, 23, 59),
      );
      expect(result, hasLength(3));
      for (final d in result) {
        expect(d.hour, 14);
        expect(d.minute, 30);
      }
    });

    test('to before from returns empty list', () {
      final result = enumerateOccurrences(
        anchor: DateTime(2026, 7),
        recurrence: TaskRecurrence.daily,
        from: DateTime(2026, 7, 10),
        to: DateTime(2026, 7),
      );
      expect(result, isEmpty);
    });
  });

  group('advanceRecurringDueDate', () {
    test('daily recurrence moves to today after missed days', () {
      final result = advanceRecurringDueDate(
        from: DateTime(2026, 7),
        recurrence: TaskRecurrence.daily,
        hasTime: false,
        now: DateTime(2026, 7, 4, 15),
      );

      expect(result, DateTime(2026, 7, 4));
    });

    test('weekly recurrence moves only when the next week starts', () {
      final beforeNext = advanceRecurringDueDate(
        from: DateTime(2026, 7),
        recurrence: TaskRecurrence.weekly,
        hasTime: false,
        now: DateTime(2026, 7, 21),
      );
      final atNext = advanceRecurringDueDate(
        from: DateTime(2026, 7),
        recurrence: TaskRecurrence.weekly,
        hasTime: false,
        now: DateTime(2026, 7, 22),
      );

      expect(beforeNext, DateTime(2026, 7, 15));
      expect(atNext, DateTime(2026, 7, 22));
    });

    test('weekdays recurrence skips the weekend', () {
      final result = advanceRecurringDueDate(
        from: DateTime(2026, 7, 3),
        recurrence: TaskRecurrence.weekdays,
        hasTime: false,
        now: DateTime(2026, 7, 6),
      );

      expect(result, DateTime(2026, 7, 6));
    });

    test('monthly recurrence preserves the clamped calendar day', () {
      final result = advanceRecurringDueDate(
        from: DateTime(2026, 1, 31),
        recurrence: TaskRecurrence.monthly,
        hasTime: false,
        now: DateTime(2026, 2, 28),
      );

      expect(result, DateTime(2026, 2, 28));
    });

    test('monthly recurrence returns to the anchor day after February', () {
      final result = advanceRecurringDueDate(
        from: DateTime(2026, 1, 31),
        recurrence: TaskRecurrence.monthly,
        hasTime: false,
        now: DateTime(2026, 3),
      );

      expect(result, DateTime(2026, 2, 28));

      final nextMonth = advanceRecurringDueDate(
        from: result,
        recurrence: TaskRecurrence.monthly,
        hasTime: false,
        now: DateTime(2026, 4),
        anchor: DateTime(2026, 1, 31),
      );

      expect(nextMonth, DateTime(2026, 3, 31));
    });

    test('a timed occurrence stays current until the next time starts', () {
      final beforeNext = advanceRecurringDueDate(
        from: DateTime(2026, 7, 4, 9),
        recurrence: TaskRecurrence.daily,
        hasTime: true,
        now: DateTime(2026, 7, 4, 10),
      );
      final atNext = advanceRecurringDueDate(
        from: DateTime(2026, 7, 4, 9),
        recurrence: TaskRecurrence.daily,
        hasTime: true,
        now: DateTime(2026, 7, 5, 9),
      );

      expect(beforeNext, DateTime(2026, 7, 4, 9));
      expect(atNext, DateTime(2026, 7, 5, 9));
    });
  });

  group('latestOccurrenceOnOrBefore', () {
    // Reference: the series produced by stepping nextDueDate one occurrence
    // at a time, which is what the constant-time formula must reproduce.
    DateTime? stepped(
      DateTime anchor,
      TaskRecurrence recurrence,
      DateTime today,
    ) {
      bool started(DateTime d) => !DateTime(
        d.year,
        d.month,
        d.day,
      ).isAfter(DateTime(today.year, today.month, today.day));
      if (!started(anchor)) return null;
      var current = anchor;
      while (true) {
        final next = nextDueDate(
          from: current,
          recurrence: recurrence,
          anchorDay: anchor.day,
        )!;
        if (!started(next)) return current;
        current = next;
      }
    }

    test('matches stepping the series for every recurrence', () {
      final anchors = [
        for (var d = 0; d < 40; d += 3) DateTime(2025, 1, 26 + d, 9, 30),
        DateTime(2024, 1, 31, 8),
        DateTime(2024, 2, 29),
        DateTime(2025, 3, 30, 23, 59),
        DateTime(2025, 6, 1),
      ];
      for (final recurrence in TaskRecurrence.values) {
        for (final anchor in anchors) {
          for (var offset = -3; offset < 500; offset += 7) {
            final today = DateTime(
              anchor.year,
              anchor.month,
              anchor.day + offset,
              offset.isEven ? 0 : 22,
            );
            expect(
              latestOccurrenceOnOrBefore(
                anchor: anchor,
                recurrence: recurrence,
                today: today,
              ),
              stepped(anchor, recurrence, today),
              reason: '$recurrence anchor=$anchor today=$today',
            );
          }
        }
      }
    });

    test('keeps a UTC anchor in UTC and preserves the time of day', () {
      final anchor = DateTime.utc(2025, 1, 31, 7, 45);
      final result = latestOccurrenceOnOrBefore(
        anchor: anchor,
        recurrence: TaskRecurrence.monthly,
        today: DateTime(2025, 3, 15),
      )!;
      expect(result.isUtc, isTrue);
      expect(result, DateTime.utc(2025, 2, 28, 7, 45));
    });
  });
}
