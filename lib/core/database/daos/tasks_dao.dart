import 'package:drift/drift.dart';

import '../../../features/tasks/domain/task_recurrence.dart';
import '../../utils/date_time_extensions.dart';

import '../database.dart';
import '../tables/tasks.dart';
import 'task_completions_dao.dart';

part 'tasks_dao.g.dart';

@DriftAccessor(tables: [Tasks])
class TasksDao extends DatabaseAccessor<AppDatabase> with _$TasksDaoMixin {
  TasksDao(super.db);

  /// Optional reference to the completions DAO. Set by the database
  /// during construction (see `database.dart`).
  TaskCompletionsDao? completionsDao;

  Stream<List<TaskData>> watchTodayTasks() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return (select(tasks)
          ..where((t) => t.dueDate.isSmallerThanValue(today.add(const Duration(days: 1))))
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
          ..where((t) => userId == null ? const Constant(true) : t.userId.equals(userId))
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
            (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.asc),
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
            (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.asc),
          ]))
        .get();
  }

  Future<void> insertTask(TaskData task) async {
    await into(tasks).insert(task, mode: InsertMode.replace);
  }

  Future<void> updateTask(TasksCompanion companion) async {
    final now = DateTime.now();
    final updatedCompanion = companion.copyWith(
      updatedAt: Value(now),
      isDirty: const Value(true),
    );
    await (update(tasks)..where((t) => t.id.equals(companion.id.value))).write(updatedCompanion);
  }

  /// Marks the row with [id] as completed, records the completion event
  /// in the [LocalTaskCompletions] history, and — if the task is
  /// recurring — schedules the next occurrence.
  ///
  /// Recurrence rules (case-sensitive, applied to the **current** due
  /// date, falling back to "today" if the task has no due date):
  ///
  ///   * `daily`    → current due + 1 day
  ///   * `weekdays` → current due + 1 day, skipping Sat/Sun
  ///   * `weekly`   → current due + 7 days
  ///   * `monthly`  → current due + 1 calendar month, clamped to the
  ///                  last valid day if the target month is shorter
  ///   * anything else (or empty / null) → task is left as "completed"
  ///     and no new row is inserted
  ///
  /// For recurring tasks the same row is updated in place: the `dueDate`
  /// advances to the next occurrence, `completedAt` is cleared, and
  /// `status` stays `open`. Non-recurring tasks are marked `done`. The
  /// completion event is recorded in [LocalTaskCompletions]. Dirty flags
  /// are set so the sync layer propagates the change to the backend.
  ///
  /// Returns the next due date for recurring tasks, or null for
  /// non-recurring tasks.
  Future<DateTime?> completeTask(String id) async {
    final task = await (select(tasks)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (task == null) return null;

    final now = DateTime.now();
    DateTime? nextDue;

    await transaction(() async {
      // 1. Record the completion event.
      if (completionsDao != null) {
        await completionsDao!.recordCompletion(
          taskId: task.id,
          userId: task.userId,
          completedAt: now,
        );
      }

      // 2. If recurring, schedule the next occurrence on the same row.
      final recurrence = task.recurrence;
      if (recurrence != null) {
        nextDue = _nextDueDate(
          from: task.dueDate ?? now,
          recurrence: recurrence,
        );
        if (nextDue != null) {
          await (update(tasks)..where((t) => t.id.equals(id))).write(
            TasksCompanion(
              dueDate: Value(nextDue),
              completedAt: const Value(null),
              status: const Value('open'),
              updatedAt: Value(now),
              isDirty: const Value(true),
            ),
          );
          return;
        }
      }

      // 3. Non-recurring or unsupported recurrence: mark completed.
      await (update(tasks)..where((t) => t.id.equals(id))).write(
        TasksCompanion(
          status: const Value('done'),
          completedAt: Value(now),
          updatedAt: Value(now),
          isDirty: const Value(true),
        ),
      );
    });

    return nextDue;
  }

  /// Hard-deletes a task (used when the user removes a task from the
  /// editor). Prefer [softDeleteTask] for app-level delete so the
  /// tombstone can sync to the backend.
  Future<void> deleteTaskById(String id) async {
    await (delete(tasks)..where((t) => t.id.equals(id))).go();
  }

  /// Marks [id] as soft-deleted (sets `deletedAt = now` and flips
  /// `isDirty = true`). The row stays in the table — sync is the only
  /// thing that removes it for good.
  Future<void> softDeleteTask(String id) async {
    await (update(tasks)..where((t) => t.id.equals(id))).write(
      TasksCompanion(
        deletedAt: Value(DateTime.now().toUtc()),
        isDirty: const Value(true),
      ),
    );
  }

  /// Reverses a completion: clears `completedAt`, sets `status` back to
  /// `pending`, and marks the row dirty so the change propagates.
  Future<void> reopenTask(String id) async {
    await (update(tasks)..where((t) => t.id.equals(id))).write(
      TasksCompanion(
        status: const Value('open'),
        completedAt: const Value(null),
        updatedAt: Value(DateTime.now()),
        isDirty: const Value(true),
      ),
    );
  }

  /// Returns every task that has unsynced local changes.
  Future<List<TaskData>> getDirtyTasks() {
    return (select(tasks)..where((t) => t.isDirty.equals(true))).get();
  }

  /// Flips the dirty flag off only if the row's [updatedAt] still matches
  /// [pushedUpdatedAt] — if the user edited while the push was in flight
  /// the flag stays on so the next sync round picks up the new change.
  Future<void> clearDirtyFlag(String id, DateTime pushedUpdatedAt) async {
    await (update(tasks)
          ..where((t) => t.id.equals(id) & t.updatedAt.equals(pushedUpdatedAt)))
        .write(const TasksCompanion(isDirty: Value(false)));
  }

  /// Stores a task that came back from the backend. Uses
  /// `insertOnConflictUpdate` so a re-pulled row replaces the local copy
  /// in place, and always sets [isDirty] to `false` so the row does not
  /// get pushed back to the server.
  Future<void> upsertFromRemote(TaskData task) async {
    final incoming = task.copyWith(isDirty: false);
    await into(tasks).insertOnConflictUpdate(incoming);
  }

  Future<void> reorderTasksBatch(List<String> orderedIds) async {
    await batch((b) {
      for (var i = 0; i < orderedIds.length; i++) {
        b.update(
          tasks,
          TasksCompanion(position: Value(i)),
          where: (t) => t.id.equals(orderedIds[i]),
        );
      }
    });
  }

  /// Runs [action] inside a Drift [Transaction] so that all batched
  /// task writes in a single save are either committed or rolled
  /// back together.
  Future<void> runInTransaction(Future<void> Function() action) async {
    await transaction(() async {
      await action();
    });
  }
}

/// Pure helper that returns the next due date for a given [recurrence]
/// rule starting from [from]. Returns `null` when the rule is not
/// recognised, in which case the caller leaves the task as completed
/// without scheduling a follow-up.
DateTime? _nextDueDate({
  required DateTime from,
  required TaskRecurrence recurrence,
}) {
  final today = DateTime.now().startOfDay;

  DateTime? raw;
  switch (recurrence) {
    case TaskRecurrence.daily:
      raw = from.add(const Duration(days: 1));
    case TaskRecurrence.weekdays:
      var day = from.add(const Duration(days: 1));
      // Skip Saturday (6) and Sunday (7) — Dart's DateTime.weekday is
      // 1-based with Monday=1.
      while (day.weekday == DateTime.saturday ||
          day.weekday == DateTime.sunday) {
        day = day.add(const Duration(days: 1));
      }
      raw = day;
    case TaskRecurrence.weekly:
      raw = from.add(const Duration(days: 7));
    case TaskRecurrence.monthly:
      final desiredMonth = from.month + 1;
      final overflow = desiredMonth > 12;
      final year = from.year + (overflow ? 1 : 0);
      final month = overflow ? 1 : desiredMonth;
      // Clamp the day to the last valid day of the target month so e.g.
      // Jan 31 → Feb 28 (or 29 in a leap year) rather than overflowing
      // into March.
      final lastDayOfTarget = DateTime(year, month + 1, 0).day;
      final day = from.day <= lastDayOfTarget ? from.day : lastDayOfTarget;
      raw = DateTime(year, month, day);
  }

  if (raw.isBefore(today)) {
    raw = today;
  }

  return raw;
}
