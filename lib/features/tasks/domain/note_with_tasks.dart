import '../../../core/database/database.dart';
import '../../../core/utils/date_time_extensions.dart';
import 'task_recurrence.dart';

/// Immutable view-model for a task shown in the presentation layer.
///
/// Mirrors the Drift-generated [TaskData] one-to-one but exposes only the
/// fields the UI cares about and adds convenience predicates
/// ([isCompleted], [isOverdue], [isDueToday], [isRepeating]) so widgets
/// never have to repeat the same `status == 'done'` / date math.
///
/// One-way conversion only — there is no `toData()` because every write
/// goes through the repository, which is in charge of bumping `updatedAt`
/// and flipping the `isDirty` flag.
class TaskModel {
  const TaskModel({
    required this.id,
    required this.userId,
    required this.noteId,
    required this.title,
    required this.status,
    required this.position,
    required this.dueDate,
    required this.completedAt,
    required this.recurrence,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String userId;
  final String noteId;
  final String title;
  final String status;
  final int position;
  final DateTime? dueDate;
  final DateTime? completedAt;
  final TaskRecurrence? recurrence;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Builds a presentation-layer [TaskModel] from a Drift row. Centralised
  /// here so the rest of the app never has to know about [TaskData].
  factory TaskModel.fromData(TaskData d) {
    return TaskModel(
      id: d.id,
      userId: d.userId,
      noteId: d.noteId,
      title: d.title,
      status: d.status,
      position: d.position,
      dueDate: d.dueDate?.toLocal(),
      completedAt: d.completedAt?.toLocal(),
      recurrence: d.recurrence,
      createdAt: d.createdAt.toLocal(),
      updatedAt: d.updatedAt.toLocal(),
    );
  }

  bool get isCompleted => status == 'done';
  bool get isPending => status == 'open';

  bool get isRepeating => recurrence != null;

  bool get isOverdue {
    if (isCompleted || dueDate == null) return false;
    return dueDate!.isBefore(DateTime.now().startOfDay);
  }

  bool get isDueToday {
    if (dueDate == null) return false;
    return dueDate!.isSameDayAs(DateTime.now());
  }
}
