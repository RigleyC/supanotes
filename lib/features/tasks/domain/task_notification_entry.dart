import 'package:supanotes/features/tasks/domain/task_schedule_identity.dart';

/// Identifies the persisted source of a task reminder.
///
/// This is deliberately separate from the list presentation union. A note
/// task and an independent task may have the same block/id, but they must
/// never share a platform notification.
enum TaskNotificationEntrySource { standalone, note }

class TaskNotificationEntry {
  const TaskNotificationEntry({
    required this.id,
    required this.title,
    required this.dueDate,
    required this.hasTime,
    required this.reminder,
    this.source = TaskNotificationEntrySource.note,
    this.noteId,
  });

  final String id;
  final String title;
  final DateTime dueDate;
  final bool hasTime;
  final String? reminder;
  final TaskNotificationEntrySource source;

  /// The owning note for a note task. It is null for standalone tasks.
  final String? noteId;

  /// Stable cache identity for one source item, excluding its occurrence.
  /// The occurrence itself is part of [TaskNotificationId].
  String get sourceKey => source == TaskNotificationEntrySource.note
      ? 'note:${noteId ?? ''}:$id'
      : 'task:$id';

  @override
  bool operator ==(Object other) =>
      other is TaskNotificationEntry &&
      id == other.id &&
      title == other.title &&
      sameScheduledAt(dueDate, other.dueDate, hasTime: hasTime) &&
      hasTime == other.hasTime &&
      reminder == other.reminder &&
      source == other.source &&
      noteId == other.noteId;

  @override
  int get hashCode => Object.hash(
    id,
    title,
    scheduledAtKey(dueDate, hasTime: hasTime),
    hasTime,
    reminder,
    source,
    noteId,
  );
}
