import 'package:supanotes/features/tasks/domain/note_task_reader.dart';
import 'package:supanotes/features/tasks/domain/task_list_item.dart';
import 'package:supanotes/features/tasks/domain/task_occurrence.dart';

/// Reads note task blocks for the Tasks list.
///
/// This reader intentionally does not depend on [TaskNotificationEntry]. A
/// task list represents the current visible occurrence, including overdue
/// recurring occurrences; notification scheduling is allowed to choose a
/// different future occurrence and therefore has a separate reader.
class NoteTaskListReader {
  const NoteTaskListReader({this.clock});

  final DateTime Function()? clock;

  List<NoteTask> read({
    required String noteId,
    required String noteTitle,
    required String documentJson,
    required bool hideCompleted,
  }) {
    final policy = TaskOccurrencePolicy(clock: clock);
    final result = <NoteTask>[];
    for (final parsed in parseNoteTaskBlocks(documentJson)) {
      final occurrence = policy.resolveCurrent(
        taskId: parsed.blockId,
        anchor: parsed.dueDate,
        recurrence: parsed.recurrence,
        hasTime: parsed.hasTime,
        completedAtByScheduledAt: parsed.completions,
      );
      final isCompleted = parsed.recurrence == null
          ? parsed.isCompleted || occurrence?.isCompleted == true
          : occurrence?.isCompleted == true;
      if (hideCompleted && isCompleted) continue;

      result.add(
        NoteTask(
          noteId: noteId,
          blockId: parsed.blockId,
          title: parsed.title,
          noteTitle: noteTitle,
          dueDate: occurrence?.scheduledAt ?? parsed.dueDate,
          hasTime: parsed.hasTime,
          isCompleted: isCompleted,
          recurrenceRule: parsed.recurrence?.name,
          completions: parsed.completions,
          lastCompletedAt: parsed.lastCompletedAt,
        ),
      );
    }
    return result;
  }

  /// Reads note tasks without applying the open-list visibility filter.
  ///
  /// History needs the canonical completion metadata even when a note's
  /// `hide_completed` preference is enabled.
  List<NoteTask> readForHistory({
    required String noteId,
    required String noteTitle,
    required String documentJson,
  }) {
    return [
      for (final parsed in parseNoteTaskBlocks(documentJson))
        NoteTask(
          noteId: noteId,
          blockId: parsed.blockId,
          title: parsed.title,
          noteTitle: noteTitle,
          dueDate: parsed.dueDate,
          hasTime: parsed.hasTime,
          isCompleted: parsed.isCompleted,
          recurrenceRule: parsed.recurrence?.name,
          completions: parsed.completions,
          lastCompletedAt: parsed.lastCompletedAt,
        ),
    ];
  }
}
