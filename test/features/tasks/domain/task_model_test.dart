import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/features/tasks/domain/task_model.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';

void main() {
  test('maps an overdue recurring projection to its current occurrence', () {
    final now = DateTime(2026, 8, 4, 12);
    final model = TaskModel.fromData(
      TaskData(
        id: 'task-1',
        userId: 'user-1',
        noteId: 'note-1',
        title: 'Daily task',
        status: 'open',
        position: '0',
        dueDate: DateTime(2026, 8, 1),
        hasTime: false,
        completedAt: null,
        recurrence: TaskRecurrence.daily,
        reminder: null,
        createdAt: DateTime(2026, 8, 1),
        updatedAt: DateTime(2026, 8, 1),
        deletedAt: null,
      ),
      now: now,
    );

    expect(model.dueDate, DateTime(2026, 8, 4));
  });

  test('does not advance a completed recurring projection', () {
    final model = TaskModel.fromData(
      TaskData(
        id: 'task-2',
        userId: 'user-1',
        noteId: 'note-1',
        title: 'Completed daily task',
        status: 'done',
        position: '0',
        dueDate: DateTime(2026, 8, 1),
        hasTime: false,
        completedAt: DateTime(2026, 8, 1),
        recurrence: TaskRecurrence.daily,
        reminder: null,
        createdAt: DateTime(2026, 8, 1),
        updatedAt: DateTime(2026, 8, 1),
        deletedAt: null,
      ),
      now: DateTime(2026, 8, 4),
    );

    expect(model.dueDate, DateTime(2026, 8, 1));
  });

  test('keeps a timed occurrence until its next scheduled time starts', () {
    final model = TaskModel.fromData(
      TaskData(
        id: 'task-3',
        userId: 'user-1',
        noteId: 'note-1',
        title: 'Timed daily task',
        status: 'open',
        position: '0',
        dueDate: DateTime(2026, 8, 4, 9),
        hasTime: true,
        completedAt: null,
        recurrence: TaskRecurrence.daily,
        reminder: null,
        createdAt: DateTime(2026, 8, 1),
        updatedAt: DateTime(2026, 8, 1),
        deletedAt: null,
      ),
      now: DateTime(2026, 8, 4, 10),
    );

    expect(model.dueDate, DateTime(2026, 8, 4, 9));
  });
}
