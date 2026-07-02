import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/tasks_repository.dart';
import '../../domain/task_recurrence.dart';

final taskControllerProvider =
    AsyncNotifierProvider.autoDispose<TaskController, void>(TaskController.new);

class TaskController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> updateTaskMetadata({
    required String taskId,
    required String title,
    DateTime? dueDate,
    TaskRecurrence? recurrence,
    bool clearDueDate = false,
    bool clearRecurrence = false,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref
          .read(tasksRepositoryProvider)
          .updateTask(
            taskId,
            title: title,
            dueDate: dueDate,
            recurrence: recurrence,
            clearDueDate: clearDueDate,
            clearRecurrence: clearRecurrence,
          ),
    );
  }
}
