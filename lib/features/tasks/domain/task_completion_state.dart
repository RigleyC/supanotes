import 'package:supanotes/features/tasks/domain/task_occurrence.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';

/// Single definition of a completed task for every read surface.
///
/// A recurring task derives completion from its occurrence history. A one-shot
/// task keeps the persisted checkbox as the fallback for tasks without an
/// anchor, so a checked task without a schedule still reads as complete.
bool isTaskOccurrenceCompleted({
  required bool isComplete,
  required TaskRecurrence? recurrence,
  required TaskOccurrence? occurrence,
}) {
  if (recurrence != null) return occurrence?.isCompleted ?? false;
  return isComplete || occurrence?.isCompleted == true;
}
