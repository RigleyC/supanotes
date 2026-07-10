import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';

void main() {
  test('completing a recurring task updates the same row with the next due date', () async {
    final db = AppDatabase.test();
    db.tasksDao.completionsDao = db.taskCompletionsDao;
    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);
    final due = todayStart;
    await db.tasksDao.insertTask(TaskData(
      id: 'task-1',
      userId: 'user-1',
      noteId: 'note-1',
      title: 'Daily standup',
      status: 'open',
      position: '0',
      recurrence: TaskRecurrence.daily,
      dueDate: due,
      completedAt: null,
      createdAt: todayStart,
      updatedAt: todayStart,
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
    expect(task.dueDate, todayStart.add(const Duration(days: 1)));
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
      position: '0',
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
      position: '0',
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
    // Use August 31 → September (30 days) to test clamp, both in future.
    final due = DateTime(2026, 8, 31);
    await db.tasksDao.insertTask(TaskData(
      id: 'task-4',
      userId: 'user-1',
      noteId: 'note-1',
      title: 'Monthly review',
      status: 'open',
      position: '0',
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
    expect(task.dueDate!.month, 9);
    expect(task.dueDate!.day, 30);  // Sep has 30 days, clamped from 31

    await db.close();
  });

  test('catchUpRecurringTasks advances overdue daily task to today', () async {
    final db = AppDatabase.test();
    db.tasksDao.completionsDao = db.taskCompletionsDao;
    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);
    final twoDaysAgo = todayStart.subtract(const Duration(days: 2));

    await db.tasksDao.insertTask(TaskData(
      id: 'catchup-1',
      userId: 'user-1',
      noteId: 'note-1',
      title: 'Daily standup',
      status: 'open',
      position: '0',
      recurrence: TaskRecurrence.daily,
      dueDate: twoDaysAgo,
      completedAt: null,
      createdAt: twoDaysAgo,
      updatedAt: twoDaysAgo,
      deletedAt: null,
      isDirty: true,
    ));

    await db.tasksDao.catchUpRecurringTasks();

    final tasks = await db.select(db.tasks).get();
    expect(tasks, hasLength(1));
    final task = tasks.single;
    expect(task.status, 'open');
    expect(task.dueDate, todayStart);
    expect(task.isDirty, isTrue);

    // No completion records — the missed days are just skipped
    final completions = await db.select(db.localTaskCompletions).get();
    expect(completions, isEmpty);

    await db.close();
  });

  test('catchUpRecurringTasks does not touch tasks already due today or in the future', () async {
    final db = AppDatabase.test();
    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);

    await db.tasksDao.insertTask(TaskData(
      id: 'catchup-2',
      userId: 'user-1',
      noteId: 'note-1',
      title: 'Already current',
      status: 'open',
      position: '0',
      recurrence: TaskRecurrence.daily,
      dueDate: todayStart,
      completedAt: null,
      createdAt: todayStart,
      updatedAt: todayStart,
      deletedAt: null,
      isDirty: false,
    ));

    await db.tasksDao.catchUpRecurringTasks();

    final tasks = await db.select(db.tasks).get();
    final task = tasks.single;
    expect(task.dueDate, todayStart);
    expect(task.isDirty, isFalse); // Not touched

    await db.close();
  });

  test('catchUpRecurringTasks does not touch non-recurring tasks', () async {
    final db = AppDatabase.test();
    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);
    final yesterday = todayStart.subtract(const Duration(days: 1));

    await db.tasksDao.insertTask(TaskData(
      id: 'catchup-3',
      userId: 'user-1',
      noteId: 'note-1',
      title: 'One-off overdue',
      status: 'open',
      position: '0',
      recurrence: null,
      dueDate: yesterday,
      completedAt: null,
      createdAt: yesterday,
      updatedAt: yesterday,
      deletedAt: null,
      isDirty: false,
    ));

    await db.tasksDao.catchUpRecurringTasks();

    final tasks = await db.select(db.tasks).get();
    final task = tasks.single;
    expect(task.dueDate, yesterday); // Unchanged
    expect(task.isDirty, isFalse);

    await db.close();
  });

  test('adding recurrence to a completed task re-opens it with next due date', () async {
    final db = AppDatabase.test();
    db.tasksDao.completionsDao = db.taskCompletionsDao;
    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);
    final completedAt = todayStart.subtract(const Duration(hours: 2));

    await db.tasksDao.insertTask(TaskData(
      id: 'reopen-1',
      userId: 'user-1',
      noteId: 'note-1',
      title: 'Was one-off',
      status: 'done',
      position: '0',
      recurrence: null,
      dueDate: todayStart,
      completedAt: completedAt,
      createdAt: todayStart,
      updatedAt: todayStart,
      deletedAt: null,
      isDirty: false,
    ));

    await db.tasksDao.updateTask(TasksCompanion(
      id: const Value('reopen-1'),
      recurrence: const Value(TaskRecurrence.daily),
    ));

    final tasks = await db.select(db.tasks).get();
    final task = tasks.single;
    expect(task.status, 'open');
    expect(task.completedAt, isNull);
    expect(task.recurrence, TaskRecurrence.daily);
    expect(task.dueDate!.isAfter(todayStart.subtract(const Duration(days: 1))), isTrue);
    expect(task.isDirty, isTrue);

    await db.close();
  });

  test('completing a 3-day overdue daily task completes today and advances to tomorrow', () async {
    final db = AppDatabase.test();
    db.tasksDao.completionsDao = db.taskCompletionsDao;
    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);
    final threeDaysAgo = todayStart.subtract(const Duration(days: 3));

    await db.tasksDao.insertTask(TaskData(
      id: 'complete-catchup-1',
      userId: 'user-1',
      noteId: 'note-1',
      title: 'Overdue 3 days',
      status: 'open',
      position: '0',
      recurrence: TaskRecurrence.daily,
      dueDate: threeDaysAgo,
      completedAt: null,
      createdAt: threeDaysAgo,
      updatedAt: threeDaysAgo,
      deletedAt: null,
      isDirty: true,
    ));

    final result = await db.tasksDao.completeTask('complete-catchup-1');
    final nextDue = result.nextDue;

    // Should advance to tomorrow (today + 1)
    final tomorrowStart = todayStart.add(const Duration(days: 1));
    expect(nextDue, tomorrowStart);
    expect(result.previousDue, threeDaysAgo);

    // Task row: open, due tomorrow
    final tasks = await db.select(db.tasks).get();
    final task = tasks.single;
    expect(task.status, 'open');
    expect(task.dueDate, tomorrowStart);

    // Exactly 1 completion record
    final completions = await db.select(db.localTaskCompletions).get();
    expect(completions, hasLength(1));

    await db.close();
  });
}

