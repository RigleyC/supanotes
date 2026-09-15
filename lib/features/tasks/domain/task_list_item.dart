import 'task.dart';

class NoteTask {
  const NoteTask({
    required this.noteId,
    required this.blockId,
    required this.title,
    this.noteTitle,
    this.dueDate,
    this.hasTime = false,
    this.isCompleted = false,
  });
  final String noteId;
  final String blockId;
  final String title;
  final String? noteTitle;
  final DateTime? dueDate;
  final bool hasTime;
  final bool isCompleted;
}

class TaskListItem {
  const TaskListItem.task(Task value) : task = value, note = null;
  const TaskListItem.note(NoteTask value) : note = value, task = null;
  final Task? task;
  final NoteTask? note;
  bool get isStandalone => task != null;
  bool get isNote => note != null;
}
