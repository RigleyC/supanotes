import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';

void main() {
  test('completing a task marks it done and records completion', () async {
    final db = AppDatabase.test();
    db.tasksDao.completionsDao = db.taskCompletionsDao;
    final today = DateTime.now();
    await db.tasksDao.insertTask(TaskData(
      id: 'task-1',
      userId: 'user-1',
      noteId: 'note-1',
      title: 'Daily standup',
      status: 'open',
      position: '0',
      recurrence: TaskRecurrence.daily,
      dueDate: today,
      hasTime: false,
      completedAt: null,
      createdAt: today,
      updatedAt: today,
      deletedAt: null,
    ));

    await db.tasksDao.completeTask('task-1');

    final tasks = await db.select(db.tasks).get();
    expect(tasks, hasLength(1));
    final task = tasks.single;
    expect(task.id, 'task-1');
    expect(task.status, 'done');
    expect(task.completedAt, isNotNull);

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
      hasTime: false,
      completedAt: null,
      createdAt: DateTime(2026, 6, 15),
      updatedAt: DateTime(2026, 6, 15),
      deletedAt: null,
    ));

    await db.tasksDao.completeTask('task-2');

    final tasks = await db.select(db.tasks).get();
    expect(tasks, hasLength(1));
    final task = tasks.single;
    expect(task.status, 'done');
    expect(task.completedAt, isNotNull);

    await db.close();
  });

  test('completing a recurring task without due date marks it done', () async {
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
      hasTime: false,
      completedAt: null,
      createdAt: DateTime(2026, 6, 15),
      updatedAt: DateTime(2026, 6, 15),
      deletedAt: null,
    ));

    await db.tasksDao.completeTask('task-3');

    final tasks = await db.select(db.tasks).get();
    expect(tasks, hasLength(1));
    final task = tasks.single;
    expect(task.status, 'done');
    expect(task.completedAt, isNotNull);

    await db.close();
  });

  test('completing a monthly recurring task marks it done', () async {
    final db = AppDatabase.test();
    db.tasksDao.completionsDao = db.taskCompletionsDao;
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
      hasTime: false,
      completedAt: null,
      createdAt: due,
      updatedAt: due,
      deletedAt: null,
    ));

    await db.tasksDao.completeTask('task-4');

    final tasks = await db.select(db.tasks).get();
    final task = tasks.single;
    expect(task.status, 'done');
    expect(task.completedAt, isNotNull);

    await db.close();
  });

  test('catchUpRecurringTasks is a no-op in per-occurrence model', () async {
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
      hasTime: false,
      completedAt: null,
      createdAt: twoDaysAgo,
      updatedAt: twoDaysAgo,
      deletedAt: null,
    ));

    await db.tasksDao.catchUpRecurringTasks();

    final tasks = await db.select(db.tasks).get();
    expect(tasks, hasLength(1));
    final task = tasks.single;
    expect(task.status, 'open');
    // In the per-occurrence model, dueDate is the anchor and never advances.
    expect(task.dueDate, twoDaysAgo);

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
      hasTime: false,
      completedAt: null,
      createdAt: todayStart,
      updatedAt: todayStart,
      deletedAt: null,
    ));

    await db.tasksDao.catchUpRecurringTasks();

    final tasks = await db.select(db.tasks).get();
    final task = tasks.single;
    expect(task.dueDate, todayStart); // Not touched

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
      hasTime: false,
      completedAt: null,
      createdAt: yesterday,
      updatedAt: yesterday,
      deletedAt: null,
    ));

    await db.tasksDao.catchUpRecurringTasks();

    final tasks = await db.select(db.tasks).get();
    final task = tasks.single;
    expect(task.dueDate, yesterday); // Unchanged

    await db.close();
  });

  test('adding recurrence to a completed task re-opens it and keeps dueDate as anchor', () async {
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
      hasTime: false,
      completedAt: completedAt,
      createdAt: todayStart,
      updatedAt: todayStart,
      deletedAt: null,
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
    // In per-occurrence model, dueDate stays as anchor — not advanced.
    expect(task.dueDate, todayStart);
    await db.close();
  });

  test('completing an overdue task marks it done with no next date', () async {
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
      hasTime: false,
      completedAt: null,
      createdAt: threeDaysAgo,
      updatedAt: threeDaysAgo,
      deletedAt: null,
    ));

    final result = await db.tasksDao.completeTask('complete-catchup-1');
    final nextDue = result.nextDue;

    expect(nextDue, isNull);
    expect(result.previousDue, threeDaysAgo);

    // Task row: done
    final tasks = await db.select(db.tasks).get();
    final task = tasks.single;
    expect(task.status, 'done');
    expect(task.completedAt, isNotNull);
    expect(task.dueDate, threeDaysAgo);

    // Exactly 1 completion record
    final completions = await db.select(db.localTaskCompletions).get();
    expect(completions, hasLength(1));

    await db.close();
  });
}

