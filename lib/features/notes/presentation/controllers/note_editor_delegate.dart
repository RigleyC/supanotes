import 'package:supanotes/features/notes/domain/attachment_model.dart';
import 'package:supanotes/features/notes/domain/task_entry.dart';
import 'package:supanotes/features/tasks/domain/task_model.dart';

class NoteEditorDelegate {
  final Future<void> Function(String noteId, String markdown, List<TaskEntry> tasks) snapshotSave;
  final Future<void> Function(String noteId)? emptyNoteExit;
  final void Function(bool hasContent)? onHasContentChanged;
  final void Function(TaskModel? task, Future<void> Function() flushSnapshot)? onTaskLongPress;
  final Future<void> Function(String taskId)? onTaskComplete;
  final Future<void> Function(String taskId)? onTaskReopen;
  final Future<AttachmentModel> Function(String noteId, String filePath, String mimeType)? onUploadFile;

  const NoteEditorDelegate({
    required this.snapshotSave,
    this.emptyNoteExit,
    this.onHasContentChanged,
    this.onTaskLongPress,
    this.onTaskComplete,
    this.onTaskReopen,
    this.onUploadFile,
  });
}
