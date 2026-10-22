class NoteEditorDelegate {
  const NoteEditorDelegate({
    this.onTaskLongPress,
    this.onTaskComplete,
    this.onTaskReopen,
  });
  final void Function(String taskId)? onTaskLongPress;
  final Future<DateTime?> Function(String taskId)? onTaskComplete;
  final Future<void> Function(String taskId, DateTime? scheduledAt)?
  onTaskReopen;
}
