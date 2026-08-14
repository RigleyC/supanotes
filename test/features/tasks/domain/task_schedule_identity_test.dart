import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/tasks/domain/task_schedule_identity.dart';

void main() {
  group('scheduledAtKey', () {
    test('uses the calendar date for all-day representations', () {
      final localMidnight = DateTime(2026, 8, 12);
      final utcRepresentation = DateTime.utc(2026, 8, 12, 3);

      expect(
        sameScheduledAt(localMidnight, utcRepresentation, hasTime: false),
        isTrue,
      );
      expect(
        scheduledAtKey(localMidnight, hasTime: false),
        '2026-08-12T00:00:00.000',
      );
    });

    test('uses wall-clock time for timed representations', () {
      final localTime = DateTime(2026, 8, 12, 9, 30);
      final utcRepresentation = DateTime.utc(2026, 8, 12, 9, 30);

      expect(
        sameScheduledAt(localTime, utcRepresentation, hasTime: true),
        isTrue,
      );
      expect(
        scheduledAtKey(utcRepresentation, hasTime: true),
        '2026-08-12T09:30:00.000',
      );
    });

    test('does not merge different all-day dates', () {
      expect(
        sameScheduledAt(
          DateTime(2026, 8, 12),
          DateTime(2026, 8, 13),
          hasTime: false,
        ),
        isFalse,
      );
    });
  });
}
