import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/database.dart';
import '../../../core/utils/date_time_extensions.dart';
import '../domain/task_date_filter.dart';
import '../domain/task_model.dart';
import '../domain/task_recurrence.dart';
import 'local/tasks_local_repository.dart';

/// Presentation-facing facade over the local tasks database.
///
/// Wraps the lower-level [TasksLocalRepository] and exposes every read in
/// terms of [TaskModel] so widgets never have to import Drift types, and
/// concentrates the date filtering (overdue / today / undated) that the
/// "Hoje" screen needs into one place.
abstract class ITasksRepository {
  String get userId;
  Stream<List<TaskModel>> watchTodayTasks();
  Stream<List<TaskModel>> watchOverdueTasks();
  Stream<List<TaskModel>> watchTodayDueTasks();
  Stream<List<TaskModel>> watchUndatedOpenTasks();
  Stream<List<TaskModel>> watchByNote(String noteId);
  Future<TaskModel> createTask({
    required String noteId,
    required String title,
    DateTime? dueDate,
    TaskRecurrence? recurrence,
    String position = 'a0',
  });
  Future<({DateTime? nextDue, DateTime? previousDue})> completeTask(String id);
  Future<void> reopenTask(String id, {DateTime? originalDueDate});
  Future<void> updateTask(
    String id, {
    String? title,
    DateTime? dueDate,
    TaskRecurrence? recurrence,
    String? position,
    bool clearDueDate = false,
    bool clearRecurrence = false,
  });
  Future<void> deleteTask(String id);
  Future<void> reorderTasks(String noteId, List<String> orderedIds);
  Future<void> catchUpRecurringTasks();
}

class TasksRepository implements ITasksRepository {
  TasksRepository(this._local) {
    // Fire-and-forget: advance overdue recurring tasks to today.
    // Errors are swallowed — the fast-forward in _nextDueDate is a safety net.
    _local.catchUpRecurringTasks();
  }

  final TasksLocalRepository _local;
  final Uuid _uuid = const Uuid();

  @override
  String get userId => _local.userId;

  @override
  Future<void> catchUpRecurringTasks() => _local.catchUpRecurringTasks();

  // ---------------------------------------------------------------------------
  // Reads
  // ---------------------------------------------------------------------------

  /// All tasks whose due date is today or in the past, ordered: overdue
  /// first (oldest first), then today, then completed at the bottom.
  @override
  Stream<List<TaskModel>> watchTodayTasks() {
    return _local
        .watchOpenTasks()
        .map(_splitByDeadlineAndMap)
        .map(_orderForToday);
  }

  /// Tasks whose due date is strictly before today (and still pending).
  @override
  Stream<List<TaskModel>> watchOverdueTasks() {
    return _local.watchOpenTasks().map((rows) {
      return TaskDateFilter.overdue(
        rows.map(TaskModel.fromData).toList(),
        today: DateTime.now().startOfDay,
      );
    });
  }

  /// Tasks whose due date is exactly today (and still pending).
  @override
  Stream<List<TaskModel>> watchTodayDueTasks() {
    return _local.watchOpenTasks().map((rows) {
      return TaskDateFilter.today(
        rows.map(TaskModel.fromData).toList(),
        today: DateTime.now().startOfDay,
      );
    });
  }

  /// Pending tasks that have no due date at all — surfaced in the
  /// collapsible "Sem data" section.
  @override
  Stream<List<TaskModel>> watchUndatedOpenTasks() {
    return _local.watchOpenTasks().map((rows) {
      return TaskDateFilter.undated(rows.map(TaskModel.fromData).toList());
    });
  }

  /// Every task attached to [noteId], in their stable `position` order,
  /// pending first then completed. Useful from the note editor.
  @override
  Stream<List<TaskModel>> watchByNote(String noteId) {
    return _local.watchNoteTasks(noteId).map((rows) {
      return rows.map(TaskModel.fromData).toList();
    });
  }

  // ---------------------------------------------------------------------------
  // Mutations
  // ---------------------------------------------------------------------------

  /// Inserts a brand-new task. Generates the UUID, stamps `userId` from
  /// the bound repository, and marks the row dirty so the next sync round
  /// pushes it to the backend.
  @override
  Future<TaskModel> createTask({
    required String noteId,
    required String title,
    DateTime? dueDate,
    TaskRecurrence? recurrence,
    String position = 'a0',
  }) async {
    final id = _uuid.v4();
    await _local.createTask(
      id: id,
      noteId: noteId,
      title: title,
      recurrence: recurrence,
      dueDate: dueDate,
      position: position,
    );
    return TaskModel(
      id: id,
      userId: _local.userId,
      noteId: noteId,
      title: title,
      status: 'open',
      position: position,
      dueDate: dueDate,
      completedAt: null,
      recurrence: recurrence,
      hasTime: false,
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    );
  }

  /// Delegates to the DAO, which marks the row completed and, if the
  /// task is recurring, schedules the next occurrence in the same
  /// transaction.
  @override
  Future<({DateTime? nextDue, DateTime? previousDue})> completeTask(String id) => _local.completeTask(id);

  /// Reverses a completion: clears `completedAt` and re-opens the task.
  @override
  Future<void> reopenTask(String id, {DateTime? originalDueDate}) => _local.reopenTask(id, originalDueDate: originalDueDate);

  /// Partial update of the task with [id]. Pass `null` for any field
  /// that should not change. An explicit `Value(null)` (via the
  /// [clearDueDate] / [clearRecurrence] helpers below) is required to
  /// wipe a nullable column.
  @override
  Future<void> updateTask(
    String id, {
    String? title,
    DateTime? dueDate,
    TaskRecurrence? recurrence,
    String? position,
    bool clearDueDate = false,
    bool clearRecurrence = false,
  }) async {
    final companion = TasksCompanion(
      id: Value(id),
      title: title == null ? const Value.absent() : Value(title),
      dueDate: clearDueDate
          ? const Value(null)
          : (dueDate == null ? const Value.absent() : Value(dueDate)),
      recurrence: clearRecurrence
          ? const Value(null)
          : (recurrence == null ? const Value.absent() : Value(recurrence)),
      position: position == null ? const Value.absent() : Value(position),
    );
    await _local.updateTask(companion);
  }

  /// Soft-deletes the task. The row stays in the database with
  /// `deletedAt` set so the tombstone reaches the backend on the next
  /// sync round.
  @override
  Future<void> deleteTask(String id) => _local.softDeleteTask(id);

  /// Rewrites the `position` of every task in [noteId] to match
  /// [orderedIds]. Wrapped in a single transaction via DAO's batch update.
  @override
  Future<void> reorderTasks(String noteId, List<String> orderedIds) async {
    // Requires exposing DAO from local repo, or passing down orderedIds.
    // Let's call a new method on local repo:
    await _local.reorderTasksBatch(orderedIds);
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  List<TaskModel> _splitByDeadlineAndMap(List<TaskData> rows) {
    return rows.map(TaskModel.fromData).toList();
  }

  List<TaskModel> _orderForToday(List<TaskModel> tasks) {
    tasks.sort((a, b) {
      if (a.isCompleted != b.isCompleted) {
        return a.isCompleted ? 1 : -1;
      }
      final aDue = a.dueDate;
      final bDue = b.dueDate;
      if (aDue == null && bDue == null) return 0;
      if (aDue == null) return 1;
      if (bDue == null) return -1;
      return aDue.compareTo(bDue);
    });
    return tasks;
  }
}

/// Riverpod entry point for the feature-level [TasksRepository]. Reads
/// [tasksLocalRepositoryProvider] which already gates on the signed-in
/// user, so this provider is itself safe to read only when authenticated.
final tasksRepositoryProvider = Provider.autoDispose<ITasksRepository>((ref) {
  final local = ref.watch(tasksLocalRepositoryProvider);
  return TasksRepository(local);
});

// ---------------------------------------------------------------------------
// Convenience stream providers — re-exported as `StreamProvider`s so widgets
// can `ref.watch` them without managing the `.map()` plumbing themselves.
// ---------------------------------------------------------------------------

/// Stream of every task visible on the "Hoje" surface (overdue + today +
/// undated), used by the today screen for the global empty-state check.
final todayTasksStreamProvider = StreamProvider.autoDispose<List<TaskModel>>((
  ref,
) {
  return ref.watch(tasksRepositoryProvider).watchTodayTasks();
});

final overdueTasksStreamProvider = StreamProvider.autoDispose<List<TaskModel>>((
  ref,
) {
  return ref.watch(tasksRepositoryProvider).watchOverdueTasks();
});

final todayDueTasksStreamProvider = StreamProvider.autoDispose<List<TaskModel>>(
  (ref) {
    return ref.watch(tasksRepositoryProvider).watchTodayDueTasks();
  },
);

final undatedOpenTasksStreamProvider =
    StreamProvider.autoDispose<List<TaskModel>>((ref) {
      return ref.watch(tasksRepositoryProvider).watchUndatedOpenTasks();
    });
