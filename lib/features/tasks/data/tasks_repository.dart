import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart' show TaskData;
import '../../../core/utils/date_time_extensions.dart';
import '../domain/task_date_filter.dart';
import '../domain/task_model.dart';
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
}

class TasksRepository implements ITasksRepository {
  TasksRepository(this._local);

  final TasksLocalRepository _local;

  @override
  String get userId => _local.userId;

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

  /// All tasks belonging to [noteId], mapped to domain.
  @override
  Stream<List<TaskModel>> watchByNote(String noteId) {
    return _local
        .watchNoteTasks(noteId)
        .map((list) => list.map(TaskModel.fromData).toList());
  }

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
