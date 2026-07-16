import 'package:supanotes/features/tasks/domain/task_model.dart';

class NoteEditorDelegate {
  final void Function(bool hasContent)? onHasContentChanged;
  final void Function(TaskModel? task, Future<void> Function() flushSnapshot)?
  onTaskLongPress;
  final Future<DateTime?> Function(String taskId)? onTaskComplete;
  final Future<void> Function(String taskId)? onTaskReopen;
  final void Function(String taskId, DateTime nextDue)? onRecurringTaskComplete;

  const NoteEditorDelegate({
    this.onHasContentChanged,
    this.onTaskLongPress,
    this.onTaskComplete,
    this.onTaskReopen,
    this.onRecurringTaskComplete,
  });
}
