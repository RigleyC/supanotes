import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/core/utils/recurrence.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';

void main() {
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
