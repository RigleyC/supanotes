import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/features/tasks/data/task_repository.dart';
import 'package:supanotes/features/tasks/domain/task.dart';

/// Presentation-facing task mutations.
///
/// The controller deliberately contains no optimistic state of its own. The
/// repository owns the local transaction and outbox, while providers refresh
/// the UI from the resulting Drift stream.
class TaskController {
  const TaskController(this._repository);

  final TaskRepository _repository;

  Future<void> create(Task task) async {
    await _repository.create(task);
  }

  Future<void> update(Task task) async {
    await _repository.update(task);
  }

  Future<void> complete(
    String taskId, {
    String? scheduledAt,
    DateTime? completedAt,
  }) async {
    final occurrence =
        scheduledAt ??
        DateTime.now().toIso8601String();
    await _repository.completeOccurrence(
      taskId: taskId,
      scheduledAt: occurrence,
      completedAt: completedAt,
    );
  }

  Future<void> reopen(String taskId, {String? scheduledAt}) async {
    final occurrence =
        scheduledAt ??
        DateTime.now().toIso8601String();
    await _repository.reopenOccurrence(
      taskId: taskId,
      scheduledAt: occurrence,
    );
  }

  Future<void> delete(String taskId) async {
    await _repository.delete(taskId);
  }
}

final taskControllerProvider = Provider.autoDispose<TaskController>((ref) {
  return TaskController(ref.watch(taskRepositoryProvider));
});

/// Stream used by the standalone editor. Keeping this provider close to the
/// controller makes the editor independent from database row details.
final standaloneTaskProvider = StreamProvider.autoDispose.family<Task?, String>(
  (ref, taskId) {
    return ref
        .watch(taskRepositoryProvider)
        .watchTask(taskId)
        .map((row) => row == null ? null : TaskRepository.fromData(row));
  },
);
