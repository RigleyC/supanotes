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
    NotifierProvider<TaskNotificationScheduler, Map<String, DateTime>>(
  TaskNotificationScheduler.new,
);

class TaskNotificationScheduler extends Notifier<Map<String, DateTime>> {
  @override
  Map<String, DateTime> build() {
    ref.listen(openTasksStreamProvider, (_, next) {
      next.whenOrNull(data: _reschedule);
    });
    return {};
  }

  void _reschedule(List<TaskData> tasks) {
    final service = ref.read(localNotificationServiceProvider);
    final now = DateTime.now();

    final newSchedule = <String, DateTime>{};
    for (final task in tasks) {
      final due = task.dueDate;
      if (due == null) continue;
      final scheduledDate = task.hasTime
          ? due
          : DateTime(due.year, due.month, due.day, 9, 0);
      if (scheduledDate.isAfter(now)) {
        newSchedule[task.id] = scheduledDate;
      }
    }

    for (final id in state.keys) {
      if (!newSchedule.containsKey(id)) {
        service.cancel(id.hashCode);
      }
    }

    for (final MapEntry(:key, :value) in newSchedule.entries) {
      if (state[key] != value) {
        final task = tasks.firstWhere((t) => t.id == key);
        service.scheduleTaskNotification(key, task.title, value);
      }
    }

    state = newSchedule;
  }
}
