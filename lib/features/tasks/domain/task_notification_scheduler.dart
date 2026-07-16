import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/features/tasks/data/local/tasks_local_repository.dart';

final openTasksStreamProvider = StreamProvider.autoDispose<List<TaskData>>(
  (ref) {
    try {
      final repo = ref.watch(tasksLocalRepositoryProvider);
      return repo.watchOpenTasks();
    } catch (_) {
      return const Stream.empty();
    }
  },
);

final taskNotificationSchedulerProvider =
    NotifierProvider<TaskNotificationScheduler, Set<String>>(
  TaskNotificationScheduler.new,
);

class TaskNotificationScheduler extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    ref.listen(openTasksStreamProvider, (_, next) {
      next.whenOrNull(data: _reschedule);
    });
    return {};
  }

  void _reschedule(List<TaskData> tasks) {
    final service = ref.read(localNotificationServiceProvider);

    final dueTasks =
        tasks.where((t) => t.dueDate != null).toList();
    final newIds = dueTasks.map((t) => t.id).toSet();

    for (final id in state.difference(newIds)) {
      service.cancel(id.hashCode);
    }

    for (final task in dueTasks) {
      final due = task.dueDate!;
      final scheduledDate = task.hasTime
          ? due
          : DateTime(due.year, due.month, due.day, 9, 0);
      if (scheduledDate.isAfter(DateTime.now())) {
        service.scheduleTaskNotification(task.id, task.title, scheduledDate);
      }
    }

    state = newIds;
  }
}
