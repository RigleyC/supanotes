import 'task.dart';
import 'task_completion_record.dart';

class NoteTask {
  const NoteTask({
    required this.noteId,
    required this.blockId,
    required this.title,
    this.noteTitle,
    this.dueDate,
    this.hasTime = false,
    this.isCompleted = false,
    this.completedAt,
    this.recurrenceRule,
    this.completions = const {},
    this.lastCompletedAt,
    this.completionHistory = const [],
    this.createdAt,
  });

  final String noteId;
  final String blockId;
  final String title;
  final String? noteTitle;
  final DateTime? dueDate;
  final bool hasTime;
  final bool isCompleted;
  final DateTime? completedAt;
  final String? recurrenceRule;
  final Map<DateTime, DateTime> completions;
  final DateTime? lastCompletedAt;
  final List<TaskCompletionRecord> completionHistory;
  final DateTime? createdAt;

  bool get isRecurring => recurrenceRule != null;

  String get uiKey => 'note:$noteId:$blockId';
}

class TaskListItem {
  const TaskListItem.task(
    this.task, {
    this.scheduledAt,
    this.explicitScheduledAt = false,
    this.scheduledHasTime,
    this.isCompleted = false,
    this.completedAt,
  }) : note = null;
  const TaskListItem.note(
    this.note, {
    this.scheduledAt,
    this.explicitScheduledAt = false,
    this.scheduledHasTime,
    this.isCompleted = false,
    this.completedAt,
  }) : task = null;

  final Task? task;
  final NoteTask? note;

  /// The occurrence currently shown in the list. For non-recurring tasks this
  /// normally equals the persisted due date; for recurring tasks it can be a
  /// later visible occurrence while the persisted anchor remains unchanged.
  final DateTime? scheduledAt;
  final bool explicitScheduledAt;
  final bool? scheduledHasTime;
  final bool isCompleted;
  final DateTime? completedAt;

  bool get isStandalone => task != null;
  bool get isNote => note != null;

  String get source => isStandalone ? 'standalone' : 'note';

  String get taskId => isStandalone ? task!.id : note!.blockId;

  String? get noteId => note?.noteId;

  String? get blockId => note?.blockId;

  String get uiKey => isStandalone
      ? 'standalone:${task!.id}'
      : 'note:${note!.noteId}:${note!.blockId}';

  DateTime? get dueDate => explicitScheduledAt
      ? scheduledAt
      : scheduledAt ?? (isStandalone ? task!.dueDate : note!.dueDate);

  bool get hasTime =>
      scheduledHasTime ?? (isStandalone ? task!.hasTime : note!.hasTime);

  DateTime? get createdAt => isStandalone ? task!.createdAt : note!.createdAt;
}
