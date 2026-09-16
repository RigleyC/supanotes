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
import 'package:supanotes/features/tasks/domain/task_notification_source.dart';
import 'package:supanotes/features/tasks/domain/task_notification_time.dart';

final AsyncNotifierProvider<TaskNotificationScheduler, Map<String, DateTime>>
taskNotificationSchedulerProvider =
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

  /// Occurrence values persisted alongside the notification-time cache. The
  /// map is needed to reconstruct the source-aware ID after a process restart.
  final Map<String, DateTime> _cachedOccurrences = {};

  List<TaskNotificationEntry>? _latestStandaloneTasks;
  List<TaskNotificationEntry>? _latestNoteTasks;

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
          final value = entry.value;
          if (value is String) {
            // Legacy cache shape: key -> notification time. The old ID used
            // the task/block ID only and is cancelled before new scheduling.
            cachedSchedule[entry.key] = DateTime.parse(value);
            continue;
          }
          final object = (value as Map).cast<String, dynamic>();
          cachedSchedule[entry.key] = DateTime.parse(
            object['notificationAt'] as String,
          );
          final scheduledAt = object['scheduledAt'] as String?;
          if (scheduledAt != null) {
            _cachedOccurrences[entry.key] = DateTime.parse(scheduledAt);
          }
        }
      } catch (e) {
        dev.log('[Scheduler] Failed to parse cached schedule: $e');
      }
    }

    dev.log(
      '[Scheduler] Loaded ${cachedSchedule.length} cached schedules. Setting up task listener',
    );

    // Both sources are always reconciled. The list's note-task toggle is a
    // presentation preference and intentionally does not reach this path.
    ref.listen(standaloneTaskNotificationSourceProvider, (_, next) {
      next.when(
        data: (tasks) {
          _latestStandaloneTasks = tasks;
          _onSourceChanged();
        },
        loading: () => dev.log('[Scheduler] Standalone stream loading...'),
        error: (e, st) => dev.log('[Scheduler] Standalone stream error: $e'),
      );
    }, fireImmediately: true);
    ref.listen(noteTaskNotificationSourceProvider, (_, next) {
      next.when(
        data: (tasks) {
          _latestNoteTasks = tasks;
          _onSourceChanged();
        },
        loading: () => dev.log('[Scheduler] Note stream loading...'),
        error: (e, st) => dev.log('[Scheduler] Note stream error: $e'),
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

  void _onSourceChanged() {
    final standalone = _latestStandaloneTasks;
    final notes = _latestNoteTasks;
    if (standalone == null || notes == null) return;
    _onTasksChanged([
      ...standalone,
      ...notes,
    ]);
  }

  Future<void> _reschedule(List<TaskNotificationEntry> tasks) async {
    final now = DateTime.now();
    dev.log(
      '[Scheduler] _reschedule called. Total open tasks: ${tasks.length}. now=$now',
    );

    final service = ref.read(localNotificationServiceProvider);
    final currentUserId = _currentUserId();

    // Build a source-aware map to diff against previous snapshot and cached
    // state. Equal IDs from the two sources must remain separate entries.
    final newTaskMap = <String, TaskNotificationEntry>{};
    for (final task in tasks) {
      newTaskMap[task.sourceKey] = task;
    }

    // Load the persisted cached schedule for cancellation and reuse.
    final currentState = state.asData?.value ?? <String, DateTime>{};

    // The persisted cache may have been written by the old scheduler, whose
    // ID was hash(userId:taskId). Remove that platform ID before scheduling
    // any source-aware replacement. This also handles old note reminders,
    // because their legacy namespace used the block ID.
    await _cancelLegacyNotifications(
      service: service,
      currentUserId: currentUserId,
      currentState: currentState,
      newTaskMap: newTaskMap,
    );

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
    await _reconcilePlatform(
      service,
      currentUserId,
      limitedSchedule,
      newTaskMap,
    );

    dev.log(
      '[Scheduler] Done. Scheduled: ${limitedSchedule.length} notifications',
    );
    state = AsyncValue.data(limitedSchedule);

    await _cacheSchedule(currentUserId, limitedSchedule);
  }

  Future<void> _cancelLegacyNotifications({
    required LocalNotificationService service,
    required String currentUserId,
    required Map<String, DateTime> currentState,
    required Map<String, TaskNotificationEntry> newTaskMap,
  }) async {
    final legacyIds = <int>{};
    for (final key in currentState.keys) {
      // New cache keys carry their source discriminator. A raw task/block ID
      // is necessarily from the old cache format.
      if (!key.startsWith('task:') && !key.startsWith('note:')) {
        legacyIds.add(TaskNotificationId.legacyForTask(currentUserId, key));
      }
    }
    for (final entry in newTaskMap.values) {
      // A source-aware task may still have a pending old notification from a
      // previous release even when its cache row was evicted.
      legacyIds.add(
        entry.source == TaskNotificationEntrySource.note
            ? TaskNotificationId.legacyForNote(currentUserId, entry.id)
            : TaskNotificationId.legacyForTask(currentUserId, entry.id),
      );
    }
    for (final id in legacyIds) {
      await service.cancel(id);
      dev.log('[Scheduler] Cancelled legacy notification id=$id');
    }
  }

  Future<void> _cancelRemovedNotifications({
    required LocalNotificationService service,
    required String currentUserId,
    required Map<String, TaskNotificationEntry> newTaskMap,
    required Map<String, DateTime> currentState,
    required Map<String, TaskNotificationEntry>? previousMap,
  }) async {
    final removedEntries = <TaskNotificationEntry>{};
    if (previousMap != null) {
      for (final entry in previousMap.entries) {
        if (!newTaskMap.containsKey(entry.key)) {
          removedEntries.add(entry.value);
        }
      }
    }

    // On first run (_previousTaskMap is null) or as a safety net, also
    // cancel tasks that were in the persisted cache but are no longer open.
    for (final key in currentState.keys) {
      if (!newTaskMap.containsKey(key)) {
        final previous = previousMap?[key];
        if (previous != null) removedEntries.add(previous);
        // Raw keys are legacy IDs. Their platform cancellation is handled by
        // the migration pass; no source-aware ID can be reconstructed.
      }
    }

    for (final entry in removedEntries) {
      final nid = _notificationId(
        currentUserId,
        entry,
        scheduledAt: entry.dueDate,
      );
      dev.log(
        '[Scheduler] Cancelling notification for removed source=${entry.sourceKey} '
        'nid=$nid',
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
      final key = task.sourceKey;
      final notificationTime = await _scheduleTask(
        task: task,
        now: now,
        service: service,
        currentUserId: currentUserId,
        previous: previousMap?[key],
        currentState: currentState,
      );
      if (notificationTime != null) {
        schedule[key] = notificationTime;
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
    final key = task.sourceKey;

    // Unchanged entries skip the platform notification call.
    final isUnchanged = previous != null && previous == task;
    final cachedTime = currentState[key];
    if (isUnchanged && cachedTime != null && cachedTime.isAfter(now)) {
      return cachedTime;
    }

    if (!isUnchanged && (previous != null || cachedTime != null)) {
      final oldScheduledAt =
          previous?.dueDate ??
          _cachedOccurrences[key] ??
          cachedTime ??
          task.dueDate;
      final nid = _notificationId(
        currentUserId,
        task,
        scheduledAt: oldScheduledAt,
      );
      await service.cancel(nid);
      dev.log(
        '[Scheduler] Cancelled previous notification before rescheduling '
        'source=$key nid=$nid',
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
      '[Scheduler] Scheduling notification source=$key at $notificationTime',
    );
    final body = formatDueDate(due, hasTime: task.hasTime);
    final nid = _notificationId(
      currentUserId,
      task,
      scheduledAt: task.dueDate,
    );
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
      final toSave = <String, Map<String, String>>{};
      for (final entry in schedule.entries) {
        toSave[entry.key] = {
          'notificationAt': entry.value.toIso8601String(),
          if (_previousTaskMap?[entry.key] != null)
            'scheduledAt': _previousTaskMap![entry.key]!.dueDate
                .toIso8601String(),
        };
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
    Map<String, TaskNotificationEntry> desiredTasks,
  ) async {
    try {
      final pending = await service.getPendingNotificationRequests();
      final pendingIds = pending.map((p) => p.id).toSet();

      final desiredIds = desiredSchedule.keys
          .map((key) => desiredTasks[key])
          .whereType<TaskNotificationEntry>()
          .map(
            (entry) => _notificationId(
              currentUserId,
              entry,
              scheduledAt: entry.dueDate,
            ),
          )
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

  int _notificationId(
    String userId,
    TaskNotificationEntry entry, {
    required DateTime scheduledAt,
  }) {
    return entry.source == TaskNotificationEntrySource.note
        ? TaskNotificationId.forNote(
            userId: userId,
            noteId: entry.noteId ?? '',
            blockId: entry.id,
            scheduledAt: scheduledAt,
          )
        : TaskNotificationId.forTask(
            userId: userId,
            taskId: entry.id,
            scheduledAt: scheduledAt,
          );
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
