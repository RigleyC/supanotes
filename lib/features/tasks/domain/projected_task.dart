class ProjectedTask {
  final String id;
  final String noteId;
  final String title;
  final bool isCompleted;
  final String? dueDate;
  final String? recurrenceRule;
  final bool hasTime;
  final String? reminder;
  final String position;

  const ProjectedTask({
    required this.id,
    required this.noteId,
    required this.title,
    required this.isCompleted,
    this.dueDate,
    this.recurrenceRule,
    this.hasTime = false,
    this.reminder,
    required this.position,
  });
}
