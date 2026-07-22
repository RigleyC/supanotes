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
  });
}
