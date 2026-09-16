import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/features/tasks/data/task_repository.dart';
import 'package:supanotes/features/tasks/domain/task.dart';
import 'package:supanotes/features/tasks/domain/task_occurrence.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';
import 'package:supanotes/features/tasks/domain/task_schedule_identity.dart';

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
    var occurrenceKey = scheduledAt;
    if (occurrenceKey == null) {
      final task = await _requireTask(taskId);
      final visibleOccurrence = _visibleOccurrence(task);
      if (visibleOccurrence == null) {
        await _repository.update(
          task.copyWith(
            isCompleted: true,
            lastCompletedAt: (completedAt ?? DateTime.now()).toUtc(),
          ),
        );
        return;
      }
      occurrenceKey = scheduledAtKey(
        visibleOccurrence.scheduledAt,
        hasTime: task.hasTime,
      );
    }
    await _repository.completeOccurrence(
      taskId: taskId,
      scheduledAt: occurrenceKey,
      completedAt: completedAt,
    );
  }

  Future<void> reopen(String taskId, {String? scheduledAt}) async {
    var occurrenceKey = scheduledAt;
    if (occurrenceKey == null) {
      final task = await _requireTask(taskId);
      final visibleOccurrence = _visibleOccurrence(task);
      if (visibleOccurrence == null) {
        await _repository.update(
          task.copyWith(isCompleted: false, lastCompletedAt: null),
        );
        return;
      }
      occurrenceKey = scheduledAtKey(
        visibleOccurrence.scheduledAt,
        hasTime: task.hasTime,
      );
    }
    await _repository.reopenOccurrence(
      taskId: taskId,
      scheduledAt: occurrenceKey,
    );
  }

  Future<void> delete(String taskId) async {
    await _repository.delete(taskId);
  }

  Future<Task> _requireTask(String taskId) async {
    final task = await _repository.get(taskId);
    if (task == null) throw StateError('Task not found: $taskId');
    return task;
  }

  TaskOccurrence? _visibleOccurrence(Task task) {
    return const TaskOccurrencePolicy().resolveCurrent(
      taskId: '',
      anchor: task.dueDate,
      recurrence: TaskRecurrence.parse(task.recurrenceRule),
      hasTime: task.hasTime,
      completedAtByScheduledAt: readScheduledCompletions(
        task.completions,
        hasTime: task.hasTime,
      ),
    );
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
