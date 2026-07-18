import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'package:shared_preferences/shared_preferences.dart';

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
    AsyncNotifierProvider<TaskNotificationScheduler, Map<String, DateTime>>(
  TaskNotificationScheduler.new,
);

class TaskNotificationScheduler extends AsyncNotifier<Map<String, DateTime>> {
  static const _kPrefKey = 'task_notification_schedule_cache';

  @override
  Future<Map<String, DateTime>> build() async {
    dev.log('[Scheduler] Provider build() triggered');

    // Watch auth state directly. When it changes, this provider rebuilds.
    final authState = ref.watch(authControllerProvider);
    final isAuthenticated = authState.asData?.value != null;

    if (!isAuthenticated) {
      dev.log('[Scheduler] Not authenticated, sleeping');
      return {};
    }

    dev.log('[Scheduler] Authenticated, loading cached schedule state');
    final prefs = await SharedPreferences.getInstance();
    final cachedStr = prefs.getString(_kPrefKey);
    final cachedSchedule = <String, DateTime>{};
    
    if (cachedStr != null) {
      try {
        final decoded = jsonDecode(cachedStr) as Map<String, dynamic>;
        for (final entry in decoded.entries) {
          cachedSchedule[entry.key] = DateTime.parse(entry.value as String);
        }
      } catch (e) {
        dev.log('[Scheduler] Failed to parse cached schedule: $e');
      }
    }
    
    dev.log('[Scheduler] Loaded ${cachedSchedule.length} cached schedules. Setting up task listener');

    // ref.listen keeps the stream provider alive and reacts to data changes
    ref.listen(openTasksStreamProvider, (_, next) {
      next.when(
        data: _reschedule,
        loading: () => dev.log('[Scheduler] Stream loading...'),
        error: (e, st) => dev.log('[Scheduler] Stream error: $e'),
      );
    });

    return cachedSchedule;
  }

  Future<void> _reschedule(List<TaskData> tasks) async {
    final now = DateTime.now();
    dev.log('[Scheduler] _reschedule called. Total open tasks: ${tasks.length}. now=$now');

    final service = ref.read(localNotificationServiceProvider);

    final newSchedule = <String, DateTime>{};
    for (final task in tasks) {
      final due = task.dueDate;
      if (due == null) continue;

      final notificationTime = _computeNotificationTime(due, task.hasTime, task.reminder);

      if (notificationTime.isAfter(now)) {
        newSchedule[task.id] = notificationTime;
      } else {
        dev.log('[Scheduler] Task "${task.title}" SKIPPED — notificationTime $notificationTime is in the past (now=$now)');
      }
    }

    final sortedEntries = newSchedule.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    final limitedSchedule = Map.fromEntries(sortedEntries.take(30));

    final currentState = state.asData?.value ?? <String, DateTime>{};
    
    for (final id in currentState.keys) {
      if (!limitedSchedule.containsKey(id)) {
        dev.log('[Scheduler] Cancelling notification for task id=$id');
        await service.cancel(id.hashCode);
      }
    }

    for (final MapEntry(:key, :value) in limitedSchedule.entries) {
      final cachedTime = currentState[key];
      if (cachedTime == null || cachedTime.millisecondsSinceEpoch != value.millisecondsSinceEpoch) {
        final task = tasks.firstWhere((t) => t.id == key);
        final body = formatDueDate(
          task.dueDate!,
          hasTime: task.hasTime,
        );
        dev.log('[Scheduler] Scheduling notification for "${task.title}" at $value');
        await service.scheduleTaskNotification(key, task.title, body, value);
        // Small delay to prevent flooding the platform channel and blocking Android Main Thread
        await Future.delayed(const Duration(milliseconds: 100));
      } else {
        dev.log('[Scheduler] Task "${tasks.firstWhere((t) => t.id == key).title}" already scheduled');
      }
    }

    dev.log('[Scheduler] Done. Scheduled: ${limitedSchedule.length} notifications');
    state = AsyncValue.data(limitedSchedule);

    try {
      final prefs = await SharedPreferences.getInstance();
      final toSave = <String, String>{};
      for (final entry in limitedSchedule.entries) {
        toSave[entry.key] = entry.value.toIso8601String();
      }
      await prefs.setString(TaskNotificationScheduler._kPrefKey, jsonEncode(toSave));
    } catch (e) {
      dev.log('[Scheduler] Failed to cache schedule state: $e');
    }
  }

  DateTime _computeNotificationTime(DateTime due, bool hasTime, String? reminder) {
    final base = hasTime ? due : DateTime(due.year, due.month, due.day, 9, 0);

    if (reminder == null || reminder == 'at_time') return base;

    switch (reminder) {
      case '5m_before':
        return base.subtract(const Duration(minutes: 5));
      case '1h_before':
        return base.subtract(const Duration(hours: 1));
      case '1d_before':
        return base.subtract(const Duration(days: 1));
      case '9am':
        return DateTime(due.year, due.month, due.day, 9, 0);
      case '12pm':
        return DateTime(due.year, due.month, due.day, 12, 0);
      case '6pm':
        return DateTime(due.year, due.month, due.day, 18, 0);
      case '1d_before_9am':
        final dayBefore = due.subtract(const Duration(days: 1));
        return DateTime(dayBefore.year, dayBefore.month, dayBefore.day, 9, 0);
      default:
        return base;
    }
  }
}
