class NoteEditorDelegate {
  final void Function(bool hasContent)? onHasContentChanged;
  final void Function(String taskId)? onTaskLongPress;
  final Future<DateTime?> Function(String taskId)? onTaskComplete;
  final Future<void> Function(String taskId)? onTaskReopen;

  const NoteEditorDelegate({
    this.onHasContentChanged,
    this.onTaskLongPress,
    this.onTaskComplete,
    this.onTaskReopen,
  });
}
