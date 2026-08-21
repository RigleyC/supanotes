import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/tasks/domain/task_completion_command.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';

void main() {
  group('TaskCompletionCommand', () {
    test('advances a weekly task and preserves its time', () {
      final dueDate = DateTime(2026, 7, 21, 9, 30);
      final result = TaskCompletionCommand(() => DateTime(2026, 7, 21, 10))
          .complete(
            TaskSnapshot(
              dueDate: dueDate,
              hasTime: true,
              recurrence: TaskRecurrence.weekly,
            ),
          );

      expect(result.completed, isFalse);
      expect(result.previousDue, dueDate);
      expect(result.scheduledAt, dueDate);
      expect(result.nextDue, DateTime(2026, 7, 28, 9, 30));
    });

    test('moves a Friday weekday task to Monday', () {
      final dueDate = DateTime(2026, 7, 24);
      final result = TaskCompletionCommand(() => DateTime(2026, 7, 24, 12))
          .complete(
            TaskSnapshot(dueDate: dueDate, recurrence: TaskRecurrence.weekdays),
          );

      expect(result.nextDue, DateTime(2026, 7, 27));
    });

    test('uses the next calendar occurrence after early completion', () {
      final result = TaskCompletionCommand(() => DateTime(2026, 8, 10, 14))
          .complete(
            TaskSnapshot(
              dueDate: DateTime(2026, 8, 12, 9),
              hasTime: true,
              recurrence: TaskRecurrence.weekly,
              completions: {
                DateTime(2026, 8, 12, 9): DateTime(2026, 8, 10, 14),
              },
            ),
          );

      expect(result.scheduledAt, DateTime(2026, 8, 19, 9));
      expect(result.nextDue, DateTime(2026, 8, 26, 9));
    });

    test('allows a second early completion on the next occurrence', () {
      final result = TaskCompletionCommand(() => DateTime(2026, 8, 10, 15))
          .complete(
            TaskSnapshot(
              dueDate: DateTime(2026, 8, 12, 9),
              hasTime: true,
              recurrence: TaskRecurrence.weekly,
              completions: {
                DateTime(2026, 8, 12, 9): DateTime(2026, 8, 10, 14),
              },
            ),
          );

      expect(result.scheduledAt, DateTime(2026, 8, 19, 9));
      expect(result.nextDue, DateTime(2026, 8, 26, 9));
    });

    test('preserves the anchor day after a monthly short month', () {
      final result = TaskCompletionCommand(() => DateTime(2026, 3, 1, 10))
          .complete(
            TaskSnapshot(
              dueDate: DateTime(2026, 1, 31),
              recurrence: TaskRecurrence.monthly,
              completions: {
                DateTime(2026, 1, 31): DateTime(2026, 1, 31, 10),
                DateTime(2026, 2, 28): DateTime(2026, 2, 27, 10),
              },
            ),
          );

      expect(result.scheduledAt, DateTime(2026, 3, 31));
      expect(result.nextDue, DateTime(2026, 4, 30));
    });

    test(
      'uses the latest reached occurrence when the stored date is stale',
      () {
        final result = TaskCompletionCommand(() => DateTime(2026, 7, 4, 15))
            .complete(
              TaskSnapshot(
                dueDate: DateTime(2026, 7),
                recurrence: TaskRecurrence.daily,
              ),
            );

        expect(result.completed, isFalse);
        expect(result.scheduledAt, DateTime(2026, 7, 4));
        expect(result.nextDue, DateTime(2026, 7, 5));
      },
    );

    test('completes a non-recurring task without a next occurrence', () {
      final dueDate = DateTime(2026, 7);
      final result = TaskCompletionCommand(
        () => DateTime(2026, 7, 4, 15),
      ).complete(TaskSnapshot(dueDate: dueDate));

      expect(result.completed, isTrue);
      expect(result.previousDue, dueDate);
      expect(result.nextDue, isNull);
      expect(result.scheduledAt, isNull);
    });
  });
}
