import '../domain/note_model.dart';
import '../../tasks/domain/task_model.dart';

/// Container that pairs a [NoteModel] with its associated [TaskModel]s.
/// Used by the editor screen so widgets can watch a single stream instead
/// of coordinating two independent providers.
class NoteWithTasks {
  const NoteWithTasks({required this.note, required this.tasks});

  final NoteModel? note;
  final List<TaskModel> tasks;

  bool get hasNote => note != null;

  /// Quick lookup by task ID – useful for the editor’s component builder.
  Map<String, TaskModel> get taskById => {for (final t in tasks) t.id: t};
}
