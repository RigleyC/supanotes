import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/core/utils/recurrence.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';

void main() {
  group('enumerateOccurrences', () {
    test('returns empty list when anchor is null', () {
      final result = enumerateOccurrences(
        anchor: null,
        recurrence: TaskRecurrence.daily,
        from: DateTime(2026, 7, 1),
        to: DateTime(2026, 7, 10),
      );
      expect(result, isEmpty);
    });

    test('returns empty list when recurrence is null', () {
      final result = enumerateOccurrences(
        anchor: DateTime(2026, 7, 1),
        recurrence: null,
        from: DateTime(2026, 7, 1),
        to: DateTime(2026, 7, 10),
      );
      expect(result, isEmpty);
    });

    test('daily: enumerates all days in range', () {
      final result = enumerateOccurrences(
        anchor: DateTime(2026, 7, 1),
        recurrence: TaskRecurrence.daily,
        from: DateTime(2026, 7, 1),
        to: DateTime(2026, 7, 5),
      );
      expect(result, hasLength(5));
      expect(result[0], DateTime(2026, 7, 1));
      expect(result[4], DateTime(2026, 7, 5));
    });

    test('daily: starts from anchor even if anchor is before from', () {
      final result = enumerateOccurrences(
        anchor: DateTime(2026, 6, 28),
        recurrence: TaskRecurrence.daily,
        from: DateTime(2026, 7, 1),
        to: DateTime(2026, 7, 3),
      );
      expect(result, hasLength(3));
      expect(result[0], DateTime(2026, 7, 1));
      expect(result[2], DateTime(2026, 7, 3));
    });

    test('weekdays: skips weekends', () {
      // 2026-07-01 is a Wednesday
      final result = enumerateOccurrences(
        anchor: DateTime(2026, 7, 1),
        recurrence: TaskRecurrence.weekdays,
        from: DateTime(2026, 7, 1),
        to: DateTime(2026, 7, 6), // Monday
      );
      // July 1 (Wed), 2 (Thu), 3 (Fri), 6 (Mon) — Jul 4-5 are Sat-Sun
      expect(result, hasLength(4));
      expect(result.map((d) => d.weekday),
          everyElement(isNot(anyOf(DateTime.saturday, DateTime.sunday))));
    });

    test('weekly: enumerates weekly', () {
      final result = enumerateOccurrences(
        anchor: DateTime(2026, 7, 1),
        recurrence: TaskRecurrence.weekly,
        from: DateTime(2026, 7, 1),
        to: DateTime(2026, 7, 22),
      );
      // Jul 1, 8, 15, 22
      expect(result, hasLength(4));
      expect(result[0], DateTime(2026, 7, 1));
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

    test('monthly: clamps day for month with fewer days (Jan 31 -> Feb 28)', () {
      final result = enumerateOccurrences(
        anchor: DateTime(2026, 1, 31),
        recurrence: TaskRecurrence.monthly,
        from: DateTime(2026, 1, 31),
        to: DateTime(2026, 3, 31),
      );
      // Jan 31, Feb 28 (clamped), Mar 28 (nextDueDate from Feb 28)
      expect(result, hasLength(3));
      expect(result[0], DateTime(2026, 1, 31));
      expect(result[1], DateTime(2026, 2, 28));
      expect(result[2], DateTime(2026, 3, 28));
    });

    test('preserves time of day', () {
      final result = enumerateOccurrences(
        anchor: DateTime(2026, 7, 1, 14, 30),
        recurrence: TaskRecurrence.daily,
        from: DateTime(2026, 7, 1, 0, 0),
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
        anchor: DateTime(2026, 7, 1),
        recurrence: TaskRecurrence.daily,
        from: DateTime(2026, 7, 10),
        to: DateTime(2026, 7, 1),
      );
      expect(result, isEmpty);
    });
  });
}
