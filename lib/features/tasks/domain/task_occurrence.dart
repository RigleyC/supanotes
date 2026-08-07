import 'package:supanotes/core/utils/recurrence.dart';

import 'task_recurrence.dart';

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
/// This result contains no document or persistence details. Adapters decide
/// how to encode it in task metadata or a relational projection.
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
  }) {
    if (anchor == null || recurrence == null) return anchor;
    return _currentScheduledAt(
      anchor: anchor,
      recurrence: recurrence,
      hasTime: hasTime,
      now: _now(),
    );
  }

  /// Builds the current occurrence with its derived status.
  TaskOccurrence? resolveCurrent({
    required String taskId,
    required DateTime? anchor,
    required TaskRecurrence? recurrence,
    required bool hasTime,
    required Set<DateTime> completedScheduledAts,
  }) {
    if (anchor == null) return null;
    final effectiveNow = _now();
    final currentDate = recurrence == null
        ? anchor
        : _currentScheduledAt(
            anchor: anchor,
            recurrence: recurrence,
            hasTime: hasTime,
            now: effectiveNow,
          );

    final completedAt = _findCompletion(currentDate, completedScheduledAts);
    return TaskOccurrence(
      taskId: taskId,
      scheduledAt: currentDate,
      status: completedAt != null
          ? OccurrenceStatus.completed
          : _isOverdue(currentDate, effectiveNow, hasTime)
          ? OccurrenceStatus.overdue
          : OccurrenceStatus.pending,
      completedAt: completedAt,
    );
  }

  /// Calculates the document-independent result of completing an occurrence.
  TaskOccurrenceTransition complete({
    required DateTime? dueDate,
    required bool hasTime,
    required TaskRecurrence? recurrence,
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
            : _currentScheduledAt(
                anchor: dueDate,
                recurrence: recurrence,
                hasTime: hasTime,
                now: now,
              ));
    return TaskOccurrenceTransition(
      completed: false,
      nextDue: nextDueDate(from: occurrenceDate, recurrence: recurrence),
      completedAt: completedAt,
      previousDue: dueDate,
      previousHasTime: hasTime,
      scheduledAt: occurrenceDate,
    );
  }

  DateTime _now() => clock?.call() ?? DateTime.now();

  DateTime _currentScheduledAt({
    required DateTime anchor,
    required TaskRecurrence recurrence,
    required bool hasTime,
    required DateTime now,
  }) {
    return advanceRecurringDueDate(
      from: anchor,
      recurrence: recurrence,
      hasTime: hasTime,
      now: now,
    );
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
    completedScheduledAts: completedScheduledAts,
  );
  return occurrence == null ? [] : [occurrence];
}

DateTime nextOccurrenceDate({
  required DateTime from,
  required TaskRecurrence recurrence,
}) {
  return nextDueDate(from: from, recurrence: recurrence)!;
}

DateTime? _findCompletion(DateTime date, Set<DateTime> completedDates) {
  for (final d in completedDates) {
    if (d.year == date.year &&
        d.month == date.month &&
        d.day == date.day &&
        d.hour == date.hour &&
        d.minute == date.minute) {
      return d;
    }
  }
  return null;
}

bool _isOverdue(DateTime date, DateTime now, bool hasTime) {
  if (hasTime) {
    return date.isBefore(now);
  }
  final dateOnly = DateTime(date.year, date.month, date.day);
  final todayOnly = DateTime(now.year, now.month, now.day);
  return dateOnly.isBefore(todayOnly);
}
