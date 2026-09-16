import 'package:supanotes/core/database/daos/tasks_dao.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/core/auth/current_user.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/features/tasks/data/task_repository.dart';
import 'package:supanotes/features/tasks/domain/task.dart';
import 'package:supanotes/features/tasks/domain/task_notification_entry.dart';
import 'package:supanotes/features/tasks/domain/task_notification_time.dart';
import 'package:supanotes/features/tasks/domain/task_occurrence.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';

/// Supplies open reminders without depending on a presentation model.
///
/// Notification sources are intentionally separate from the task list source:
/// the list may hide note tasks, while reminders still reconcile both sources.
abstract interface class TaskNotificationSource {
  Future<List<TaskNotificationEntry>> readOpenTasks(String userId);
}

/// Reads independent tasks from their local, owner-scoped Drift table.
class StandaloneTaskNotificationSource implements TaskNotificationSource {
  StandaloneTaskNotificationSource(this._dao, {this.clock});

  final TasksDao _dao;
  final DateTime Function()? clock;

  /// Reactive counterpart used by the application scheduler.
  Stream<List<TaskNotificationEntry>> watchOpenTasks(String userId) {
    return _dao.watchTasks(userId).map(readRows);
  }

  @override
  Future<List<TaskNotificationEntry>> readOpenTasks(String userId) async {
    // This is a one-shot domain read, not provider initialization. The DAO
    // stream remains the single query definition and also keeps this source
    // consistent with the list's owner-scoped task stream.
    return readRows(await _dao.watchTasks(userId).first);
  }

  List<TaskNotificationEntry> readRows(Iterable<TaskData> rows) {
    final policy = TaskOccurrencePolicy(clock: clock);
    final result = <TaskNotificationEntry>[];
    for (final row in rows) {
      final task = TaskRepository.fromData(row);
      if (task.deletedAt != null) continue;

      final recurrence = TaskRecurrence.parse(task.recurrenceRule);
      final occurrence = policy.resolveNotificationOccurrence(
        taskId: task.id,
        anchor: task.dueDate,
        recurrence: recurrence,
        hasTime: task.hasTime,
        completedAtByScheduledAt: _taskCompletions(task),
        notificationAt: task.reminder == null
            ? null
            : (scheduledAt) => computeTaskNotificationTime(
                due: scheduledAt,
                hasTime: task.hasTime,
                reminder: task.reminder,
              ),
      );
      if (occurrence == null || occurrence.isCompleted) continue;
      if (task.isCompleted && recurrence == null) continue;

      result.add(
        TaskNotificationEntry.standalone(
          id: task.id,
          title: task.title,
          dueDate: occurrence.scheduledAt,
          hasTime: task.hasTime,
          reminder: task.reminder,
        ),
      );
    }
    return result;
  }
}

/// Reads several notification sources as one logical reminder stream.
class CombinedTaskNotificationSource implements TaskNotificationSource {
  const CombinedTaskNotificationSource(this.sources);

  final List<TaskNotificationSource> sources;

  @override
  Future<List<TaskNotificationEntry>> readOpenTasks(String userId) async {
    final entries = await Future.wait(
      sources.map((source) => source.readOpenTasks(userId)),
    );
    return [for (final sourceEntries in entries) ...sourceEntries];
  }
}

/// Reactive standalone source used by the app-level notification scheduler.
final StreamProvider<List<TaskNotificationEntry>>
standaloneTaskNotificationSourceProvider =
    StreamProvider.autoDispose<List<TaskNotificationEntry>>((ref) {
      final userId = ref.watch(currentUserIdProvider);
      if (userId == null || userId.isEmpty) return Stream.value(const []);
      return StandaloneTaskNotificationSource(
        ref.watch(tasksDaoProvider),
      ).watchOpenTasks(userId);
    });

Map<DateTime, DateTime> _taskCompletions(Task task) {
  return {
    for (final entry in task.completions.entries)
      if (DateTime.tryParse(entry.key) != null &&
          DateTime.tryParse(entry.value) != null)
        DateTime.parse(entry.key): DateTime.parse(entry.value),
  };
}
