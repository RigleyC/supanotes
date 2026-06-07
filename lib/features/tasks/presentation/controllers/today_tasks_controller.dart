import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/features/tasks/data/tasks_repository.dart';
import 'package:supanotes/features/tasks/domain/task_model.dart';

class TodayTasksState {
  final List<TaskModel> overdue;
  final List<TaskModel> today;
  final List<TaskModel> undated;

  const TodayTasksState({
    this.overdue = const [],
    this.today = const [],
    this.undated = const [],
  });

  TodayTasksState copyWith({
    List<TaskModel>? overdue,
    List<TaskModel>? today,
    List<TaskModel>? undated,
  }) =>
      TodayTasksState(
        overdue: overdue ?? this.overdue,
        today: today ?? this.today,
        undated: undated ?? this.undated,
      );
}

final todayTasksControllerProvider =
    AsyncNotifierProvider<TodayTasksController, TodayTasksState>(
  TodayTasksController.new,
);

class TodayTasksController extends AsyncNotifier<TodayTasksState> {
  @override
  Future<TodayTasksState> build() async {
    final repo = ref.read(tasksRepositoryProvider);
    final overdue = await repo.watchOverdueTasks().first;
    final today = await repo.watchTodayDueTasks().first;
    final undated = await repo.watchUndatedOpenTasks().first;
    return TodayTasksState(overdue: overdue, today: today, undated: undated);
  }

  Future<void> loadTasks() async {
    final repo = ref.read(tasksRepositoryProvider);
    final overdue = await repo.watchOverdueTasks().first;
    final today = await repo.watchTodayDueTasks().first;
    final undated = await repo.watchUndatedOpenTasks().first;
    state = AsyncValue.data(
      TodayTasksState(overdue: overdue, today: today, undated: undated),
    );
  }

  Future<void> completeTask(String id) async {
    await ref.read(tasksRepositoryProvider).completeTask(id);
    await loadTasks();
  }

  Future<void> reopenTask(String id) async {
    await ref.read(tasksRepositoryProvider).reopenTask(id);
    await loadTasks();
  }

  Future<void> deleteTask(String id) async {
    await ref.read(tasksRepositoryProvider).deleteTask(id);
    await loadTasks();
  }
}
