import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../features/tasks/domain/task_recurrence.dart';

import '../database.dart';
import '../tables/tasks.dart';
import 'task_completions_dao.dart';

part 'tasks_dao.g.dart';

@DriftAccessor(tables: [Tasks])
class TasksDao extends DatabaseAccessor<AppDatabase> with _$TasksDaoMixin {
  TasksDao(super.db);

  final Uuid _uuid = const Uuid();

  /// Optional reference to the completions DAO. Set by the database
  /// during construction (see `database.dart`).
  TaskCompletionsDao? completionsDao;

  Stream<List<TaskData>> watchTodayTasks() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return (select(tasks)
          ..where((t) => t.dueDate.isSmallerOrEqualValue(
              DateTime(today.year, today.month, today.day, 23, 59, 59)))
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
  /// The completed row stays in the table for history; the next
  /// occurrence is inserted as a brand-new row with a fresh UUID and
  /// `status = 'pending'`. Both rows are marked dirty so the sync layer
  /// pushes them to the backend.
  Future<void> completeTask(String id) async {
    final task = await (select(tasks)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (task == null) return;

    final now = DateTime.now();

    await transaction(() async {
      // 1. Mark the current row as completed.
      await (update(tasks)..where((t) => t.id.equals(id))).write(
        TasksCompanion(
          status: const Value('done'),
          completedAt: Value(now),
          updatedAt: Value(now),
          isDirty: const Value(true),
        ),
      );

      // 2. Append a row to the completion history.
      if (completionsDao != null) {
        await completionsDao!.recordCompletion(
          taskId: task.id,
          userId: task.userId,
          completedAt: now,
        );
      }

      // 3. If the task is recurring, schedule the next occurrence.
      final recurrence = task.recurrence;
      if (recurrence != null) {
        final nextDue = _nextDueDate(
          from: task.dueDate ?? now,
          recurrence: recurrence,
        );
        if (nextDue != null) {
          final next = TaskData(
            id: _uuid.v4(),
            userId: task.userId,
            noteId: task.noteId,
            title: task.title,
            status: 'open',
            position: task.position,
            recurrence: recurrence,
            dueDate: nextDue,
            createdAt: now,
            updatedAt: now,
            deletedAt: null,
            isDirty: true,
          );
          await into(tasks).insert(next, mode: InsertMode.insertOrReplace);
        }
      }
    });
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
}

/// Pure helper that returns the next due date for a given [recurrence]
/// rule starting from [from]. Returns `null` when the rule is not
/// recognised, in which case the caller leaves the task as completed
/// without scheduling a follow-up.
DateTime? _nextDueDate({
  required DateTime from,
  required TaskRecurrence recurrence,
}) {
  switch (recurrence) {
    case TaskRecurrence.daily:
      return DateTime(from.year, from.month, from.day + 1);
    case TaskRecurrence.weekdays:
      var day = DateTime(from.year, from.month, from.day + 1);
      // Skip Saturday (6) and Sunday (7) — Dart's DateTime.weekday is
      // 1-based with Monday=1.
      while (day.weekday == DateTime.saturday ||
          day.weekday == DateTime.sunday) {
        day = DateTime(day.year, day.month, day.day + 1);
      }
      return day;
    case TaskRecurrence.weekly:
      return DateTime(from.year, from.month, from.day + 7);
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
      return DateTime(year, month, day);
  }
}
