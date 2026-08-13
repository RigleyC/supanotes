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
      dueDate == other.dueDate &&
      hasTime == other.hasTime &&
      reminder == other.reminder;

  @override
  int get hashCode => Object.hash(id, title, dueDate, hasTime, reminder);
}
