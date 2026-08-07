import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/tasks.dart';
import '../../../features/tasks/domain/projected_task.dart';
import '../../../features/tasks/domain/task_recurrence.dart';

part 'tasks_dao.g.dart';

@DriftAccessor(tables: [Tasks])
class TasksDao extends DatabaseAccessor<AppDatabase> with _$TasksDaoMixin {
  TasksDao(super.db);

  /// Synchronizes projected tasks into SQLite without opening an internal transaction.
  /// Must be executed within the caller's [AppDatabase.saveProjectedDocument] transaction.
  Future<void> syncProjectedTasksForNoteTyped(
    String noteId,
    List<ProjectedTask> projectedTasks, {
    String userId = '',
  }) async {
    final existingTasks = await (select(
      tasks,
    )..where((t) => t.noteId.equals(noteId) & t.deletedAt.isNull())).get();
    final existingById = {for (final t in existingTasks) t.id: t};
    final incomingIds = projectedTasks.map((t) => t.id).toSet();

    for (final existing in existingTasks) {
      if (!incomingIds.contains(existing.id)) {
        await (update(tasks)..where((t) => t.id.equals(existing.id))).write(
          TasksCompanion(
            deletedAt: Value(DateTime.now()),
            updatedAt: Value(DateTime.now()),
          ),
        );
      }
    }

    final now = DateTime.now();
    for (var i = 0; i < projectedTasks.length; i++) {
      final taskData = projectedTasks[i];
      final id = taskData.id;
      final text = taskData.title;
      final isCompleted = taskData.isCompleted;
      final dueDateStr = taskData.dueDate;
      final dueDate = dueDateStr != null ? DateTime.tryParse(dueDateStr) : null;
      final recurrenceRule = taskData.recurrenceRule;
      final hasTime = taskData.hasTime;
      final reminder = taskData.reminder;
      final position = taskData.position;

      final old = existingById[id];
      final effectiveUserId = (old != null && old.userId.isNotEmpty)
          ? old.userId
          : userId;
      final effectiveCreatedAt = old?.createdAt ?? now;
      final effectiveCompletedAt = isCompleted
          ? (old?.completedAt ?? now)
          : null;
      final recurrenceVal = TaskRecurrence.parse(recurrenceRule);

      await into(tasks).insertOnConflictUpdate(
        TasksCompanion(
          id: Value(id),
          noteId: Value(noteId),
          userId: Value(effectiveUserId),
          title: Value(text),
          status: Value(isCompleted ? 'done' : 'open'),
          position: Value(position),
          dueDate: Value(dueDate),
          hasTime: Value(hasTime),
          reminder: Value(reminder),
          recurrence: Value(recurrenceVal),
          completedAt: Value(effectiveCompletedAt),
          createdAt: Value(effectiveCreatedAt),
          updatedAt: Value(now),
          deletedAt: const Value(null),
        ),
      );
    }
  }

  Stream<List<TaskData>> watchTodayTasks() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return (select(tasks)
          ..where(
            (t) => t.dueDate.isSmallerThanValue(
              today.add(const Duration(days: 1)),
            ),
          )
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([
            (t) => OrderingTerm(
              expression: t.status.equals('done'),
              mode: OrderingMode.asc,
            ),
            (t) => OrderingTerm(expression: t.dueDate, mode: OrderingMode.asc),
            (t) =>
                OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
          ]))
        .watch();
  }

  /// Streams every task that is still pending and not soft-deleted —
  /// used by the "open tasks" / "inbox" surfaces in the next feature
  /// wave. Pass [userId] to scope the query to a single user; omit it
  /// to stream every user's tasks (useful for tests and admin tools).
  Stream<List<TaskData>> watchOpenTasks({String? userId}) {
    return (select(tasks)
          ..where((t) => t.status.equals('open'))
          ..where((t) => t.deletedAt.isNull())
          ..where(
            (t) =>
                userId == null ? const Constant(true) : t.userId.equals(userId),
          )
          ..orderBy([
            (t) => OrderingTerm(expression: t.dueDate, mode: OrderingMode.asc),
            (t) =>
                OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
          ]))
        .watch();
  }

  Stream<List<TaskData>> watchNoteTasks(String noteId) {
    return (select(tasks)
          ..where((t) => t.noteId.equals(noteId))
          ..orderBy([
            (t) => OrderingTerm(
              expression: t.status.equals('done'),
              mode: OrderingMode.asc,
            ),
            (t) =>
                OrderingTerm(expression: t.createdAt, mode: OrderingMode.asc),
          ]))
        .watch();
  }

  Future<List<TaskData>> getNoteTasks(String noteId) {
    return (select(tasks)
          ..where((t) => t.noteId.equals(noteId))
          ..orderBy([
            (t) => OrderingTerm(
              expression: t.status.equals('done'),
              mode: OrderingMode.asc,
            ),
            (t) =>
                OrderingTerm(expression: t.createdAt, mode: OrderingMode.asc),
          ]))
        .get();
  }
}
