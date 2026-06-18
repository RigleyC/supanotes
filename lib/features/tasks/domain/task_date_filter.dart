import '../../../core/utils/date_time_extensions.dart';
import 'task_model.dart';

class TaskDateFilter {
  static List<TaskModel> overdue(List<TaskModel> tasks, {required DateTime today}) {
    return tasks
        .where((t) => !t.isCompleted && t.dueDate != null && !t.dueDate!.isSameDayAs(today) && t.dueDate!.isBefore(today))
        .toList()
      ..sort((a, b) => a.dueDate!.compareTo(b.dueDate!));
  }

  static List<TaskModel> today(List<TaskModel> tasks, {required DateTime today}) {
    return tasks
        .where((t) => t.dueDate != null && t.dueDate!.isSameDayAs(today))
        .toList()
      ..sort((a, b) => a.dueDate!.compareTo(b.dueDate!));
  }

  static List<TaskModel> undated(List<TaskModel> tasks) {
    return tasks
        .where((t) => t.dueDate == null)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }
}
