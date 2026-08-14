import 'package:flutter/foundation.dart';
import 'package:super_editor/super_editor.dart';

import '../../domain/task_recurrence.dart';
import '../../domain/task_reminder_option.dart';
import '../../domain/task_schedule_identity.dart';

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
