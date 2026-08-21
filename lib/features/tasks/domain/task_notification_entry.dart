import 'package:supanotes/features/tasks/domain/task_schedule_identity.dart';

class TaskNotificationEntry {
  const TaskNotificationEntry({
    required this.id,
    required this.title,
    required this.dueDate,
    required this.hasTime,
    required this.reminder,
  });

  final String id;
  final String title;
  final DateTime dueDate;
  final bool hasTime;
  final String? reminder;

  @override
  bool operator ==(Object other) =>
      other is TaskNotificationEntry &&
      id == other.id &&
      title == other.title &&
      sameScheduledAt(dueDate, other.dueDate, hasTime: hasTime) &&
      hasTime == other.hasTime &&
      reminder == other.reminder;

  @override
  int get hashCode => Object.hash(
    id,
    title,
    scheduledAtKey(dueDate, hasTime: hasTime),
    hasTime,
    reminder,
  );
}
