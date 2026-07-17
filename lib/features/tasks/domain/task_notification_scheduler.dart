import 'dart:developer' as dev;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/features/tasks/data/local/tasks_local_repository.dart';
import 'package:supanotes/features/tasks/domain/task_date_format.dart';

final openTasksStreamProvider = StreamProvider.autoDispose<List<TaskData>>(
  (ref) {
    try {
      final repo = ref.watch(tasksLocalRepositoryProvider);
      dev.log('[Scheduler] watchOpenTasks stream started');
      return repo.watchOpenTasks();
    } catch (e) {
      dev.log('[Scheduler] watchOpenTasks error: $e');
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
    dev.log('[Scheduler] Provider build() triggered');

    // Watch auth state directly. When it changes, this provider rebuilds.
    final authState = ref.watch(authControllerProvider);
    final isAuthenticated = authState.asData?.value != null;

    if (!isAuthenticated) {
      dev.log('[Scheduler] Not authenticated, sleeping');
      return {};
    }

    dev.log('[Scheduler] Authenticated, setting up task listener');
    
    // ref.listen keeps the stream provider alive and reacts to data changes
    ref.listen(openTasksStreamProvider, (_, next) {
      next.when(
        data: _reschedule,
        loading: () => dev.log('[Scheduler] Stream loading...'),
        error: (e, st) => dev.log('[Scheduler] Stream error: $e'),
      );
    });

    return {};
  }

  void _reschedule(List<TaskData> tasks) {
    final now = DateTime.now();
    dev.log('[Scheduler] _reschedule called. Total open tasks: ${tasks.length}. now=$now');

    final service = ref.read(localNotificationServiceProvider);

    final newSchedule = <String, DateTime>{};
    for (final task in tasks) {
      final due = task.dueDate;
      if (due == null) continue;
      
      final scheduledDate = task.hasTime
          ? due
          : DateTime(due.year, due.month, due.day, 9, 0);

      if (scheduledDate.isAfter(now)) {
        newSchedule[task.id] = scheduledDate;
      } else {
        dev.log('[Scheduler] Task "${task.title}" SKIPPED — scheduledDate $scheduledDate is in the past (now=$now)');
      }
    }

    for (final id in state.keys) {
      if (!newSchedule.containsKey(id)) {
        dev.log('[Scheduler] Cancelling notification for task id=$id');
        service.cancel(id.hashCode);
      }
    }

    for (final MapEntry(:key, :value) in newSchedule.entries) {
      if (state[key] != value) {
        final task = tasks.firstWhere((t) => t.id == key);
        final body = formatDueDate(
          task.dueDate!,
          hasTime: task.hasTime,
        );
        dev.log('[Scheduler] Scheduling notification for "${task.title}" at $value');
        service.scheduleTaskNotification(key, task.title, body, value);
      } else {
        dev.log('[Scheduler] Task "${tasks.firstWhere((t) => t.id == key).title}" already scheduled');
      }
    }

    dev.log('[Scheduler] Done. Scheduled: ${newSchedule.length} notifications');
    state = newSchedule;
  }
}
