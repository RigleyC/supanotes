import 'task_list_item.dart';

class TaskHistoryEntry {
  const TaskHistoryEntry({
    required this.task,
    required this.scheduledAt,
    required this.completedAt,
    this.note,
  });
  final TaskListItem task;
  final DateTime scheduledAt;
  final DateTime completedAt;
  final NoteTask? note;
}
