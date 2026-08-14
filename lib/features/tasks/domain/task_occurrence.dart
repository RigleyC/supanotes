import 'package:supanotes/core/utils/recurrence.dart';

import 'task_recurrence.dart';
import 'task_schedule_identity.dart';

enum OccurrenceStatus { pending, overdue, completed }

class TaskOccurrence {
  const TaskOccurrence({
    required this.taskId,
    required this.scheduledAt,
    required this.status,
    this.completedAt,
  });

  final String taskId;
  final DateTime scheduledAt;
  final OccurrenceStatus status;
  final DateTime? completedAt;

  bool get isCompleted => status == OccurrenceStatus.completed;
  bool get isOverdue => status == OccurrenceStatus.overdue;
  bool get isPending => status == OccurrenceStatus.pending;
}

/// The domain result of completing one task occurrence.
///
/// This result contains no document or persistence details. The editor
/// encodes it in task metadata through a document operation.
class TaskOccurrenceTransition {
  const TaskOccurrenceTransition({
    required this.completed,
    this.nextDue,
    required this.completedAt,
    this.previousDue,
    required this.previousHasTime,
    this.scheduledAt,
  });

  final bool completed;
  final DateTime? nextDue;
  final DateTime completedAt;
  final DateTime? previousDue;
  final bool previousHasTime;
  final DateTime? scheduledAt;
}

/// Resolves the current occurrence and recurring completion transitions.
///
/// Date arithmetic remains in [nextDueDate] and
/// [advanceRecurringDueDate]. This module owns the meaning of the current
/// occurrence so editor actions and read projections use the same policy.
class TaskOccurrencePolicy {
  const TaskOccurrencePolicy({this.clock});

  final DateTime Function()? clock;

  /// Returns the latest scheduled occurrence that has started, or `null` when
  /// the task has no anchor date.
  DateTime? currentScheduledAt({
    required DateTime? anchor,
    required TaskRecurrence? recurrence,
    required bool hasTime,
    Map<DateTime, DateTime> completedAtByScheduledAt = const {},
  }) {
    return resolveCurrent(
      taskId: '',
      anchor: anchor,
      recurrence: recurrence,
      hasTime: hasTime,
      completedAtByScheduledAt: completedAtByScheduledAt,
    )?.scheduledAt;
  }

  /// Builds the current occurrence with its derived status.
  TaskOccurrence? resolveCurrent({
    required String taskId,
    required DateTime? anchor,
    required TaskRecurrence? recurrence,
    required bool hasTime,
    Map<DateTime, DateTime> completedAtByScheduledAt = const {},
  }) {
    if (anchor == null) return null;
    final effectiveNow = _now();
    if (recurrence == null) {
      final completedAt = _findCompletion(
        anchor,
        hasTime: hasTime,
        completedAtByScheduledAt: completedAtByScheduledAt,
      );
      return TaskOccurrence(
        taskId: taskId,
        scheduledAt: anchor,
        status: completedAt != null
            ? OccurrenceStatus.completed
            : _isOverdue(anchor, effectiveNow, hasTime)
            ? OccurrenceStatus.overdue
            : OccurrenceStatus.pending,
        completedAt: completedAt,
      );
    }

    final occurrence = _resolveRecurringOccurrence(
      anchor: anchor,
      recurrence: recurrence,
      hasTime: hasTime,
      now: effectiveNow,
      completedAtByScheduledAt: completedAtByScheduledAt,
    );
    final completedAt = occurrence.completedAt;
    return TaskOccurrence(
      taskId: taskId,
      scheduledAt: occurrence.scheduledAt,
      status: completedAt != null
          ? OccurrenceStatus.completed
          : _isOverdue(occurrence.scheduledAt, effectiveNow, hasTime)
          ? OccurrenceStatus.overdue
          : OccurrenceStatus.pending,
      completedAt: completedAt,
    );
  }

  /// Returns the occurrence that should be used for a future reminder.
  ///
  /// The editor still uses [resolveCurrent], so an overdue occurrence remains
  /// visible until the next scheduled date starts. A reminder cannot be
  /// scheduled in the past, therefore an overdue recurring task points at its
  /// first future, uncompleted occurrence instead.
  TaskOccurrence? resolveNotificationOccurrence({
    required String taskId,
    required DateTime? anchor,
    required TaskRecurrence? recurrence,
    required bool hasTime,
    Map<DateTime, DateTime> completedAtByScheduledAt = const {},
    DateTime? Function(DateTime scheduledAt)? notificationAt,
  }) {
    final current = resolveCurrent(
      taskId: taskId,
      anchor: anchor,
      recurrence: recurrence,
      hasTime: hasTime,
      completedAtByScheduledAt: completedAtByScheduledAt,
    );
    if (current == null || recurrence == null || !current.isOverdue) {
      return current;
    }

    var scheduledAt = nextDueDate(
      from: current.scheduledAt,
      recurrence: recurrence,
      anchorDay: anchor!.day,
    );
    final effectiveNow = _now();
    for (var i = 0; i < 10000 && scheduledAt != null; i++) {
      final completedAt = _findCompletion(
        scheduledAt,
        hasTime: hasTime,
        completedAtByScheduledAt: completedAtByScheduledAt,
      );
      final isNotificationInFuture = notificationAt == null
          ? !_hasStarted(scheduledAt, effectiveNow, hasTime)
          : notificationAt(scheduledAt)?.isAfter(effectiveNow) ?? false;
      if (completedAt == null && isNotificationInFuture) {
        return TaskOccurrence(
          taskId: taskId,
          scheduledAt: scheduledAt,
          status: OccurrenceStatus.pending,
        );
      }

      final next = nextDueDate(
        from: scheduledAt,
        recurrence: recurrence,
        anchorDay: anchor.day,
      );
      if (next == null || next.isAtSameMomentAs(scheduledAt)) break;
      scheduledAt = next;
    }
    return current;
  }

  /// Calculates the document-independent result of completing an occurrence.
  TaskOccurrenceTransition complete({
    required DateTime? dueDate,
    required bool hasTime,
    required TaskRecurrence? recurrence,
    Map<DateTime, DateTime> completedAtByScheduledAt = const {},
    DateTime? scheduledAt,
  }) {
    final now = _now();
    final completedAt = now.toUtc();

    if (recurrence == null) {
      return TaskOccurrenceTransition(
        completed: true,
        completedAt: completedAt,
        previousDue: dueDate,
        previousHasTime: hasTime,
        scheduledAt: scheduledAt,
      );
    }

    final occurrenceDate =
        scheduledAt ??
        (dueDate == null
            ? DateTime(now.year, now.month, now.day)
            : resolveCurrent(
                taskId: '',
                anchor: dueDate,
                recurrence: recurrence,
                hasTime: hasTime,
                completedAtByScheduledAt: completedAtByScheduledAt,
              )!.scheduledAt);
    return TaskOccurrenceTransition(
      completed: false,
      nextDue: nextDueDate(
        from: occurrenceDate,
        recurrence: recurrence,
        anchorDay: dueDate?.day ?? occurrenceDate.day,
      ),
      completedAt: completedAt,
      previousDue: dueDate,
      previousHasTime: hasTime,
      scheduledAt: occurrenceDate,
    );
  }

  DateTime _now() => clock?.call() ?? DateTime.now();

  TaskOccurrence _resolveRecurringOccurrence({
    required DateTime anchor,
    required TaskRecurrence recurrence,
    required bool hasTime,
    required DateTime now,
    required Map<DateTime, DateTime> completedAtByScheduledAt,
  }) {
    var scheduledAt = anchor;
    DateTime? latestStartedUncompleted;

    for (var i = 0; i < 10000; i++) {
      final completedAt = _findCompletion(
        scheduledAt,
        hasTime: hasTime,
        completedAtByScheduledAt: completedAtByScheduledAt,
      );
      final hasStarted = _hasStarted(scheduledAt, now, hasTime);

      if (completedAt == null && !hasStarted) {
        return TaskOccurrence(
          taskId: '',
          scheduledAt: latestStartedUncompleted ?? scheduledAt,
          status: OccurrenceStatus.pending,
        );
      }

      if (hasStarted) {
        // Only the latest occurrence that has started can be active. Earlier
        // uncompleted occurrences remain history once a newer occurrence
        // starts.
        latestStartedUncompleted = completedAt == null ? scheduledAt : null;
      }

      final next = nextDueDate(
        from: scheduledAt,
        recurrence: recurrence,
        anchorDay: anchor.day,
      );
      if (next == null || next.isAtSameMomentAs(scheduledAt)) break;
      scheduledAt = next;
    }

    final result = latestStartedUncompleted ?? scheduledAt;
    return TaskOccurrence(
      taskId: '',
      scheduledAt: result,
      status: OccurrenceStatus.pending,
    );
  }

  bool _hasStarted(DateTime scheduledAt, DateTime now, bool hasTime) {
    final scheduled = canonicalScheduledAt(scheduledAt, hasTime: hasTime);
    final current = canonicalScheduledAt(now.toLocal(), hasTime: hasTime);
    return !scheduled.isAfter(current);
  }
}

List<TaskOccurrence> buildOccurrences({
  required String taskId,
  required DateTime? anchor,
  required TaskRecurrence? recurrence,
  required bool hasTime,
  required DateTime now,
  required Set<DateTime> completedScheduledAts,
  int maxCount = 365,
}) {
  if (maxCount <= 0) return [];

  final occurrence = TaskOccurrencePolicy(clock: () => now).resolveCurrent(
    taskId: taskId,
    anchor: anchor,
    recurrence: recurrence,
    hasTime: hasTime,
    completedAtByScheduledAt: {
      for (final scheduledAt in completedScheduledAts) scheduledAt: scheduledAt,
    },
  );
  return occurrence == null ? [] : [occurrence];
}

DateTime nextOccurrenceDate({
  required DateTime from,
  required TaskRecurrence recurrence,
  DateTime? anchor,
}) {
  return nextDueDate(
    from: from,
    recurrence: recurrence,
    anchorDay: anchor?.day ?? from.day,
  )!;
}

DateTime? _findCompletion(
  DateTime date, {
  required bool hasTime,
  required Map<DateTime, DateTime> completedAtByScheduledAt,
}) {
  DateTime? latestCompletion;
  for (final entry in completedAtByScheduledAt.entries) {
    final previousCompletion = latestCompletion;
    if (sameScheduledAt(entry.key, date, hasTime: hasTime) &&
        (previousCompletion == null ||
            entry.value.isAfter(previousCompletion))) {
      latestCompletion = entry.value;
    }
  }
  return latestCompletion;
}

bool _isOverdue(DateTime date, DateTime now, bool hasTime) {
  final scheduled = canonicalScheduledAt(date, hasTime: hasTime);
  final current = canonicalScheduledAt(now.toLocal(), hasTime: hasTime);
  return scheduled.isBefore(current);
}
