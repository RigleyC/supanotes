import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/core/notifications/local_notification_service.dart';
import 'package:supanotes/features/tasks/domain/note_task_notification_source.dart';
import 'package:supanotes/features/tasks/domain/task_date_format.dart';
import 'package:supanotes/features/tasks/domain/task_notification_entry.dart';
import 'package:supanotes/features/tasks/domain/task_notification_id.dart';
import 'package:supanotes/features/tasks/domain/task_notification_time.dart';

final AsyncNotifierProvider<TaskNotificationScheduler, Map<String, DateTime>> taskNotificationSchedulerProvider =
    AsyncNotifierProvider.autoDispose<
      TaskNotificationScheduler,
      Map<String, DateTime>
    >(TaskNotificationScheduler.new);

class TaskNotificationScheduler extends AsyncNotifier<Map<String, DateTime>> {
  /// Returns a per-user cache key so notifications from one account never
  /// survive into another account's session.
  static String _kPrefKey(String userId) =>
      'task_notification_schedule_cache_$userId';

  /// Cached userId from the previous build so we can detect account switches.
  String? _previousUserId;

  /// Tracks the latest pending tasks for superseding coalescing.
  List<TaskNotificationEntry>? _pendingTasks;

  /// Previous task snapshot keyed by ID for diff-based rescheduling.
  /// Only tasks whose notification-relevant fields (dueDate, hasTime, reminder)
  /// actually changed will trigger platform notification calls.
  Map<String, TaskNotificationEntry>? _previousTaskMap;

  /// Serialization chain: only one reconcile runs at a time per provider.
  Future<void> _reconcileChain = Future.value();

  /// Whether platform notification permission has already been requested
  /// during this session.
  @override
  Future<Map<String, DateTime>> build() async {
    dev.log('[Scheduler] Provider build() triggered');

    // Watch auth state directly. When it changes, this provider rebuilds.
    final authState = ref.watch(authControllerProvider);
    final user = authState.asData?.value;
    final currentUserId = user?.id ?? '';

    if (currentUserId.isEmpty) {
      dev.log('[Scheduler] Not authenticated, sleeping');
      // Cancel all platform notifications so stale notifications from a
      // previous session don't linger on the device.
      if (_previousUserId != null && _previousUserId!.isNotEmpty) {
        final service = ref.read(localNotificationServiceProvider);
        await service.cancelAll();
        dev.log('[Scheduler] Cancelled all notifications on logout');
      }
      _previousUserId = null;
      return {};
    }

    // Detect user switch — when the userId changes, wipe the old state
    // and cancel every platform notification to prevent account bleed.
    if (_previousUserId != null &&
        _previousUserId!.isNotEmpty &&
        _previousUserId != currentUserId) {
      dev.log(
        '[Scheduler] User switched from $_previousUserId to $currentUserId — cancelling all old notifications',
      );
      final service = ref.read(localNotificationServiceProvider);
      await service.cancelAll();
      // Clear the old per-user cache
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kPrefKey(_previousUserId!));
      state = const AsyncValue.data({});
    }
    _previousUserId = currentUserId;

    dev.log('[Scheduler] Authenticated, loading cached schedule state');
    final prefs = await SharedPreferences.getInstance();
    final cachedStr = prefs.getString(_kPrefKey(currentUserId));
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

    dev.log(
      '[Scheduler] Loaded ${cachedSchedule.length} cached schedules. Setting up task listener',
    );

    // ref.listen keeps the stream provider alive and reacts to data changes
    ref.listen(noteTaskNotificationSourceProvider, (_, next) {
      next.when(
        data: _onTasksChanged,
        loading: () => dev.log('[Scheduler] Stream loading...'),
        error: (e, st) => dev.log('[Scheduler] Stream error: $e'),
      );
    }, fireImmediately: true);

    return cachedSchedule;
  }

  /// Public entry point for programmatic reconciliation (e.g., on auth switch).
  ///
  /// Serialized via [_reconcileChain] so concurrent calls execute sequentially.
  /// Only the latest [tasks] set is processed if calls are queued.
  /// The [userId] for notification IDs is read from the current auth state
  /// via [_currentUserId], so this method does not accept it as a parameter.
  Future<void> reconcile({required List<TaskNotificationEntry> tasks}) {
    _onTasksChanged(tasks);
    return _reconcileChain;
  }

  void _onTasksChanged(List<TaskNotificationEntry> tasks) {
    _pendingTasks = tasks;
    _reconcileChain = _reconcileChain.then((_) async {
      try {
        final latest = _pendingTasks;
        if (latest == null) return;
        _pendingTasks = null;
        await _reschedule(latest);
      } catch (e, st) {
        dev.log('[Scheduler] _reschedule FAILED: $e', error: e, stackTrace: st);
        // Do not rethrow — the chain must survive errors so future
        // reconciliations still execute.
      }
    });
  }

  Future<void> _reschedule(List<TaskNotificationEntry> tasks) async {
    final now = DateTime.now();
    dev.log(
      '[Scheduler] _reschedule called. Total open tasks: ${tasks.length}. now=$now',
    );

    final service = ref.read(localNotificationServiceProvider);
    final currentUserId = _currentUserId();

    // Build new task map to diff against previous snapshot and cached state.
    // Indexed by ID for O(1) lookups.
    final newTaskMap = <String, TaskNotificationEntry>{};
    for (final task in tasks) {
      newTaskMap[task.id] = task;
    }

    // Load the persisted cached schedule for cancellation and reuse.
    final currentState = state.asData?.value ?? <String, DateTime>{};

    await _cancelRemovedNotifications(
      service: service,
      currentUserId: currentUserId,
      newTaskMap: newTaskMap,
      currentState: currentState,
      previousMap: _previousTaskMap,
    );

    final newSchedule = await _scheduleTasks(
      tasks: tasks,
      now: now,
      service: service,
      currentUserId: currentUserId,
      previousMap: _previousTaskMap,
      currentState: currentState,
    );

    // Store this task snapshot for the next diff
    _previousTaskMap = newTaskMap;

    // Sort and limit to 30 to avoid overwhelming the OS
    final limitedSchedule = _limitSchedule(newSchedule);

    // Reconcile against platform: list pending notifications from the OS
    // and cancel those that no longer belong.
    await _reconcilePlatform(service, currentUserId, limitedSchedule);

    dev.log(
      '[Scheduler] Done. Scheduled: ${limitedSchedule.length} notifications',
    );
    state = AsyncValue.data(limitedSchedule);

    await _cacheSchedule(currentUserId, limitedSchedule);
  }

  Future<void> _cancelRemovedNotifications({
    required LocalNotificationService service,
    required String currentUserId,
    required Map<String, TaskNotificationEntry> newTaskMap,
    required Map<String, DateTime> currentState,
    required Map<String, TaskNotificationEntry>? previousMap,
  }) async {
    final removedIds = <String>{};
    if (previousMap != null) {
      for (final id in previousMap.keys) {
        if (!newTaskMap.containsKey(id)) {
          removedIds.add(id);
        }
      }
    }

    // On first run (_previousTaskMap is null) or as a safety net, also
    // cancel tasks that were in the persisted cache but are no longer open.
    for (final id in currentState.keys) {
      if (!newTaskMap.containsKey(id)) {
        removedIds.add(id);
      }
    }

    for (final id in removedIds) {
      final nid = notificationIdForTask(currentUserId, id);
      dev.log(
        '[Scheduler] Cancelling notification for removed task id=$id nid=$nid',
      );
      await service.cancel(nid);
    }
  }

  Future<Map<String, DateTime>> _scheduleTasks({
    required List<TaskNotificationEntry> tasks,
    required DateTime now,
    required LocalNotificationService service,
    required String currentUserId,
    required Map<String, TaskNotificationEntry>? previousMap,
    required Map<String, DateTime> currentState,
  }) async {
    final schedule = <String, DateTime>{};
    for (final task in tasks) {
      final notificationTime = await _scheduleTask(
        task: task,
        now: now,
        service: service,
        currentUserId: currentUserId,
        previous: previousMap?[task.id],
        currentState: currentState,
      );
      if (notificationTime != null) {
        schedule[task.id] = notificationTime;
      }
    }
    return schedule;
  }

  Future<DateTime?> _scheduleTask({
    required TaskNotificationEntry task,
    required DateTime now,
    required LocalNotificationService service,
    required String currentUserId,
    required TaskNotificationEntry? previous,
    required Map<String, DateTime> currentState,
  }) async {
    final due = task.dueDate;

    // Unchanged entries skip the platform notification call.
    final isUnchanged = previous != null && previous == task;
    final cachedTime = currentState[task.id];
    if (isUnchanged && cachedTime != null && cachedTime.isAfter(now)) {
      return cachedTime;
    }

    if (!isUnchanged && (previous != null || cachedTime != null)) {
      final nid = notificationIdForTask(currentUserId, task.id);
      await service.cancel(nid);
      dev.log(
        '[Scheduler] Cancelled previous notification before rescheduling '
        'task id=${task.id} nid=$nid',
      );
    }

    final notificationTime = _computeNotificationTime(
      due,
      task.hasTime,
      task.reminder,
    );
    if (notificationTime == null) {
      dev.log('[Scheduler] Task id=${task.id} skipped: no notification time');
      return null;
    }
    if (!notificationTime.isAfter(now)) {
      dev.log(
        '[Scheduler] Task id=${task.id} skipped: notification time '
        '$notificationTime is in the past (now=$now)',
      );
      return null;
    }

    dev.log(
      '[Scheduler] Scheduling notification id=${task.id} at $notificationTime',
    );
    final body = formatDueDate(due, hasTime: task.hasTime);
    final nid = notificationIdForTask(currentUserId, task.id);
    await service.scheduleTaskNotification(
      nid,
      task.title,
      body,
      notificationTime,
    );
    return notificationTime;
  }

  Map<String, DateTime> _limitSchedule(Map<String, DateTime> schedule) {
    final sortedEntries = schedule.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    return Map.fromEntries(sortedEntries.take(30));
  }

  Future<void> _cacheSchedule(
    String currentUserId,
    Map<String, DateTime> schedule,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final toSave = <String, String>{};
      for (final entry in schedule.entries) {
        toSave[entry.key] = entry.value.toIso8601String();
      }
      await prefs.setString(_kPrefKey(currentUserId), jsonEncode(toSave));
    } catch (e) {
      dev.log('[Scheduler] Failed to cache schedule state: $e');
    }
  }

  /// Public method to request notification permission — called ONLY when
  /// the user explicitly saves a reminder (not during auto-reconciliation).
  Future<void> requestPermissionForReminder() async {
    final service = ref.read(localNotificationServiceProvider);
    await service.requestPermissions();
    dev.log('[Scheduler] Permission explicitly requested for reminder save');
  }

  /// Reconciles the desired schedule against the OS pending notification list.
  /// This handles cases where the OS cleared, altered, or preserved stale
  /// notifications without going through our cancel path.
  Future<void> _reconcilePlatform(
    LocalNotificationService service,
    String currentUserId,
    Map<String, DateTime> desiredSchedule,
  ) async {
    try {
      final pending = await service.getPendingNotificationRequests();
      final pendingIds = pending.map((p) => p.id).toSet();

      final desiredIds = desiredSchedule.keys
          .map((taskId) => notificationIdForTask(currentUserId, taskId))
          .toSet();

      // Cancel platform notifications whose task is no longer in the desired schedule
      for (final pendingId in pendingIds) {
        if (!desiredIds.contains(pendingId)) {
          await service.cancel(pendingId);
          dev.log(
            '[Scheduler] Platform reconciliation: cancelled orphan nid=$pendingId',
          );
        }
      }
    } catch (e) {
      dev.log('[Scheduler] Platform reconciliation failed (non-fatal): $e');
    }
  }

  String _currentUserId() {
    final authState = ref.read(authControllerProvider);
    return authState.asData?.value?.id ?? '';
  }

  DateTime? _computeNotificationTime(
    DateTime due,
    bool hasTime,
    String? reminder,
  ) {
    return computeTaskNotificationTime(
      due: due,
      hasTime: hasTime,
      reminder: reminder,
    );
  }
}
