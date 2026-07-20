import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../database.dart';
import '../tables/tasks.dart';
import '../../utils/fractional_indexing.dart';
import '../../utils/recurrence.dart';
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

  Future<void> insertTask(TaskData task) async {
    await into(tasks).insert(task, mode: InsertMode.replace);
  }

  Future<void> updateTask(TasksCompanion companion) async {
    final now = DateTime.now();
    await transaction(() async {
      var updatedCompanion = companion.copyWith(
        updatedAt: Value(now),
      );

      if (companion.recurrence.present && companion.recurrence.value != null) {
        final current = await (select(
          tasks,
        )..where((t) => t.id.equals(companion.id.value))).getSingleOrNull();

        if (current != null && current.status == 'done') {
          final recurrence = companion.recurrence.value!;
          final baseTime = current.completedAt ?? current.dueDate ?? now;
          var nextDue = nextDueDate(from: baseTime, recurrence: recurrence);
          if (nextDue != null) {
            final today = DateTime(now.year, now.month, now.day);
            nextDue = catchUpDueDate(
              from: nextDue,
              recurrence: recurrence,
              today: today,
            );
            updatedCompanion = updatedCompanion.copyWith(
              status: const Value('open'),
              dueDate: Value(nextDue),
              completedAt: const Value(null),
            );
          }
        }
      }

      await (update(
        tasks,
      )..where((t) => t.id.equals(companion.id.value))).write(updatedCompanion);
    });
  }

  Future<void> catchUpRecurringTasks() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final query = select(tasks)
      ..where((t) => t.status.equals('open'))
      ..where((t) => t.dueDate.isSmallerThanValue(today))
      ..where((t) => t.recurrence.isNotNull())
      ..where((t) => t.deletedAt.isNull());

    final overdue = await query.get();
    if (overdue.isEmpty) return;

    await transaction(() async {
      for (final task in overdue) {
        final recurrence = task.recurrence!;
        final currentDue = catchUpDueDate(
          from: task.dueDate!,
          recurrence: recurrence,
          today: today,
        );

        if (currentDue != task.dueDate) {
          await (update(tasks)..where((t) => t.id.equals(task.id))).write(
            TasksCompanion(
              dueDate: Value(currentDue),
              updatedAt: Value(now),
            ),
          );
        }
      }
    });
  }

  /// Marks the row with [id] as completed and records the completion event
  /// in the [LocalTaskCompletions] history.
  ///
  /// Recurrence logic is now centralized in [TaskCompletionCommand] (YDoc path).
  /// This method only persists the completion — the YDoc projection (sync layer)
  /// handles advancing recurring due dates.
  ///
  /// Returns the previous due date and hasTime for undo purposes.
  Future<({DateTime? nextDue, DateTime? previousDue, bool previousHasTime})> completeTask(String id) async {
    final task = await (select(
      tasks,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (task == null) return (nextDue: null, previousDue: null, previousHasTime: false);

    final now = DateTime.now();
    final previousDue = task.dueDate;

    await transaction(() async {
      if (completionsDao != null) {
        await completionsDao!.recordCompletion(
          taskId: task.id,
          userId: task.userId,
          completedAt: now,
        );
      }

      await (update(tasks)..where((t) => t.id.equals(id))).write(
        TasksCompanion(
          status: const Value('done'),
          completedAt: Value(now),
          updatedAt: Value(now),
        ),
      );
    });

    return (nextDue: null, previousDue: previousDue, previousHasTime: task.hasTime);
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
      ),
    );
  }

  /// Reverses a completion: clears `completedAt`, sets `status` back to
  /// `pending`, and marks the row dirty so the change propagates.
  Future<void> reopenTask(String id, {DateTime? originalDueDate}) async {
    debugPrint('[TasksDao] reopenTask called: id=$id, originalDueDate=$originalDueDate');
    await transaction(() async {
      await (update(tasks)..where((t) => t.id.equals(id))).write(
        TasksCompanion(
          status: const Value('open'),
          completedAt: const Value(null),
          dueDate: originalDueDate != null ? Value(originalDueDate) : const Value.absent(),
          updatedAt: Value(DateTime.now()),
        ),
      );
      debugPrint('[TasksDao] reopenTask: task row updated');

      if (completionsDao != null) {
        await completionsDao!.undoLastCompletion(id);
        debugPrint('[TasksDao] reopenTask: last completion deleted');
      }
    });
    debugPrint('[TasksDao] reopenTask: transaction committed');
  }

  /// Stores a task that came from the server projection.
  Future<void> upsertFromRemote(TaskData task) async {
    await into(tasks).insertOnConflictUpdate(task);
  }

  Future<void> reorderTasksBatch(List<String> orderedIds, String clientId) async {
    await batch((b) {
      var prev = '';
      for (var i = 0; i < orderedIds.length; i++) {
        final pos = FractionalIndex.between(prev, '', clientId);
        b.update(
          tasks,
          TasksCompanion(position: Value(pos)),
          where: (t) => t.id.equals(orderedIds[i]),
        );
        prev = pos;
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
