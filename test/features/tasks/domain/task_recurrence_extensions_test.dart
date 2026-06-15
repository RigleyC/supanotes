import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';

void main() {
  test('parses known recurrence strings', () {
    expect(TaskRecurrence.parse('daily'), TaskRecurrence.daily);
    expect(TaskRecurrence.parse('weekdays'), TaskRecurrence.weekdays);
    expect(TaskRecurrence.parse('weekly'), TaskRecurrence.weekly);
    expect(TaskRecurrence.parse('monthly'), TaskRecurrence.monthly);
  });

  test('returns null for unknown or null recurrence strings', () {
    expect(TaskRecurrence.parse('yearly'), isNull);
    expect(TaskRecurrence.parse(null), isNull);
  });
}
