import 'package:flutter/foundation.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';
import 'package:supanotes/features/tasks/domain/task_reminder_option.dart';
import 'package:supanotes/features/tasks/domain/task_schedule_identity.dart';
import 'package:super_editor/super_editor.dart';

const _unset = Object();

/// The small metadata model shared by the task sheet and editor.
///
/// This is not a persisted task model. The note document remains the source
/// of truth and the editor writes changes through document operations. The
/// completion map is display context; the sheet never edits it.
class TaskMetadataDraft {
  const TaskMetadataDraft({
    required this.scheduleAnchor,
    required this.hasTime,
    required this.recurrence,
    required this.reminder,
    this.completions = const {},
  });

  factory TaskMetadataDraft.fromTaskNode(TaskNode node) {
    final hasTime = node.metadata['hasTime'] as bool? ?? false;
    return TaskMetadataDraft(
      scheduleAnchor: parseScheduledAt(
        node.metadata['dueDate'] as String?,
        hasTime: hasTime,
      ),
      hasTime: hasTime,
      recurrence: TaskRecurrence.parse(
        node.metadata['recurrenceRule'] as String?,
      ),
      reminder: TaskReminderOption.fromValue(
        node.metadata['reminder'] as String?,
      ),
      completions: readScheduledCompletions(
        node.metadata['completions'],
        hasTime: hasTime,
      ),
    );
  }

  final DateTime? scheduleAnchor;
  final bool hasTime;
  final TaskRecurrence? recurrence;
  final TaskReminderOption? reminder;
  final Map<DateTime, DateTime> completions;

  TaskMetadataDraft copyWith({
    Object? scheduleAnchor = _unset,
    bool? hasTime,
    Object? recurrence = _unset,
    Object? reminder = _unset,
    Map<DateTime, DateTime>? completions,
  }) {
    return TaskMetadataDraft(
      scheduleAnchor: identical(scheduleAnchor, _unset)
          ? this.scheduleAnchor
          : scheduleAnchor as DateTime?,
      hasTime: hasTime ?? this.hasTime,
      recurrence: identical(recurrence, _unset)
          ? this.recurrence
          : recurrence as TaskRecurrence?,
      reminder: identical(reminder, _unset)
          ? this.reminder
          : reminder as TaskReminderOption?,
      completions: completions ?? this.completions,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is TaskMetadataDraft &&
        scheduleAnchor == other.scheduleAnchor &&
        hasTime == other.hasTime &&
        recurrence == other.recurrence &&
        reminder == other.reminder &&
        mapEquals(completions, other.completions);
  }

  @override
  int get hashCode => Object.hash(
    scheduleAnchor,
    hasTime,
    recurrence,
    reminder,
    Object.hashAllUnordered(
      completions.entries.map((entry) => Object.hash(entry.key, entry.value)),
    ),
  );
}
