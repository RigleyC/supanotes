import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';

void main() {
  test('completing a recurring task updates the same row with the next due date', () async {
    final db = AppDatabase.test();
    db.tasksDao.completionsDao = db.taskCompletionsDao;
    final due = DateTime(2026, 6, 15);
    await db.tasksDao.insertTask(TaskData(
      id: 'task-1',
      userId: 'user-1',
      noteId: 'note-1',
      title: 'Daily standup',
      status: 'open',
      position: 0,
      recurrence: TaskRecurrence.daily,
      dueDate: due,
      completedAt: null,
      createdAt: DateTime(2026, 6, 15),
      updatedAt: DateTime(2026, 6, 15),
      deletedAt: null,
      isDirty: true,
    ));

    await db.tasksDao.completeTask('task-1');

    final tasks = await db.select(db.tasks).get();
    expect(tasks, hasLength(1));
    final task = tasks.single;
    expect(task.id, 'task-1');
    expect(task.status, 'open');
    expect(task.completedAt, isNull);
    expect(task.dueDate, DateTime(2026, 6, 16));
    expect(task.recurrence, TaskRecurrence.daily);

    final completions = await db.select(db.localTaskCompletions).get();
    expect(completions, hasLength(1));
    expect(completions.single.taskId, 'task-1');

    await db.close();
  });

  test('completing a non-recurring task marks it done', () async {
    final db = AppDatabase.test();
    db.tasksDao.completionsDao = db.taskCompletionsDao;
    final due = DateTime(2026, 6, 15);
    await db.tasksDao.insertTask(TaskData(
      id: 'task-2',
      userId: 'user-1',
      noteId: 'note-1',
      title: 'One-off',
      status: 'open',
      position: 0,
      recurrence: null,
      dueDate: due,
      completedAt: null,
      createdAt: DateTime(2026, 6, 15),
      updatedAt: DateTime(2026, 6, 15),
      deletedAt: null,
      isDirty: true,
    ));

    await db.tasksDao.completeTask('task-2');

    final tasks = await db.select(db.tasks).get();
    expect(tasks, hasLength(1));
    final task = tasks.single;
    expect(task.status, 'done');
    expect(task.completedAt, isNotNull);

    await db.close();
  });

  test('completing a recurring task without due date uses today', () async {
    final db = AppDatabase.test();
    db.tasksDao.completionsDao = db.taskCompletionsDao;
    await db.tasksDao.insertTask(TaskData(
      id: 'task-3',
      userId: 'user-1',
      noteId: 'note-1',
      title: 'No due date',
      status: 'open',
      position: 0,
      recurrence: TaskRecurrence.daily,
      dueDate: null,
      completedAt: null,
      createdAt: DateTime(2026, 6, 15),
      updatedAt: DateTime(2026, 6, 15),
      deletedAt: null,
      isDirty: true,
    ));

    await db.tasksDao.completeTask('task-3');

    final tasks = await db.select(db.tasks).get();
    expect(tasks, hasLength(1));
    final task = tasks.single;
    expect(task.status, 'open');
    expect(task.completedAt, isNull);
    // _nextDueDate(from: DateTime.now(), daily) → today + 1 day, preserving time-of-day.
    // Drift stores DateTime with second precision, so compare field-by-field.
    final today = DateTime.now();
    final expectedDue = today.add(const Duration(days: 1));
    expect(task.dueDate!.year, expectedDue.year);
    expect(task.dueDate!.month, expectedDue.month);
    expect(task.dueDate!.day, expectedDue.day);
    expect(task.dueDate!.hour, expectedDue.hour);
    expect(task.dueDate!.minute, expectedDue.minute);

    await db.close();
  });

  test('completing a monthly recurring task clamps to last valid day', () async {
    final db = AppDatabase.test();
    db.tasksDao.completionsDao = db.taskCompletionsDao;
    final due = DateTime(2026, 1, 31);  // last day of January
    await db.tasksDao.insertTask(TaskData(
      id: 'task-4',
      userId: 'user-1',
      noteId: 'note-1',
      title: 'Monthly review',
      status: 'open',
      position: 0,
      recurrence: TaskRecurrence.monthly,
      dueDate: due,
      completedAt: null,
      createdAt: due,
      updatedAt: due,
      deletedAt: null,
      isDirty: true,
    ));

    await db.tasksDao.completeTask('task-4');

    final tasks = await db.select(db.tasks).get();
    final task = tasks.single;
    expect(task.status, 'open');
    expect(task.dueDate!.year, 2026);
    expect(task.dueDate!.month, 2);
    expect(task.dueDate!.day, 28);  // Feb has 28 days in 2026

    await db.close();
  });
}
