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
    this.recurrenceRule,
    this.completions = const {},
    this.lastCompletedAt,
    this.createdAt,
  });

  final String noteId;
  final String blockId;
  final String title;
  final String? noteTitle;
  final DateTime? dueDate;
  final bool hasTime;
  final bool isCompleted;
  final String? recurrenceRule;
  final Map<DateTime, DateTime> completions;
  final DateTime? lastCompletedAt;
  final DateTime? createdAt;

  bool get isRecurring => recurrenceRule != null;

  String get uiKey => 'note:$noteId:$blockId';
}

class TaskListItem {
  const TaskListItem.task(this.task, {this.scheduledAt}) : note = null;
  const TaskListItem.note(this.note, {this.scheduledAt}) : task = null;

  final Task? task;
  final NoteTask? note;

  /// The occurrence currently shown in the list. For non-recurring tasks this
  /// normally equals the persisted due date; for recurring tasks it can be a
  /// later visible occurrence while the persisted anchor remains unchanged.
  final DateTime? scheduledAt;

  bool get isStandalone => task != null;
  bool get isNote => note != null;

  String get source => isStandalone ? 'standalone' : 'note';

  String get taskId => isStandalone ? task!.id : note!.blockId;

  String? get noteId => note?.noteId;

  String? get blockId => note?.blockId;

  String get uiKey => isStandalone
      ? 'standalone:${task!.id}'
      : 'note:${note!.noteId}:${note!.blockId}';

  DateTime? get dueDate =>
      scheduledAt ?? (isStandalone ? task!.dueDate : note!.dueDate);

  bool get hasTime => isStandalone ? task!.hasTime : note!.hasTime;

  DateTime? get createdAt => isStandalone ? task!.createdAt : note!.createdAt;
}
