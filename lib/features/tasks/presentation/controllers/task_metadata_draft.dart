import 'package:super_editor/super_editor.dart';

import '../../domain/task_recurrence.dart';
import '../../domain/task_reminder_option.dart';

/// The small, editable metadata model shared by the task sheet and editor.
///
/// This is not a persisted task model. The note document remains the source
/// of truth and the editor writes changes through document operations.
class TaskMetadataDraft {
  const TaskMetadataDraft({
    required this.scheduleAnchor,
    required this.hasTime,
    required this.recurrence,
    required this.reminder,
  });

  factory TaskMetadataDraft.fromTaskNode(TaskNode node) {
    return TaskMetadataDraft(
      scheduleAnchor: DateTime.tryParse(
        node.metadata['dueDate'] as String? ?? '',
      ),
      hasTime: node.metadata['hasTime'] as bool? ?? false,
      recurrence: TaskRecurrence.parse(
        node.metadata['recurrenceRule'] as String?,
      ),
      reminder: TaskReminderOption.fromValue(
        node.metadata['reminder'] as String?,
      ),
    );
  }

  final DateTime? scheduleAnchor;
  final bool hasTime;
  final TaskRecurrence? recurrence;
  final TaskReminderOption? reminder;

  @override
  bool operator ==(Object other) {
    return other is TaskMetadataDraft &&
        scheduleAnchor == other.scheduleAnchor &&
        hasTime == other.hasTime &&
        recurrence == other.recurrence &&
        reminder == other.reminder;
  }

  @override
  int get hashCode =>
      Object.hash(scheduleAnchor, hasTime, recurrence, reminder);
}
