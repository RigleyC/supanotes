import 'package:supanotes/features/tasks/domain/task_completion_command.dart';
import 'package:supanotes/features/tasks/domain/task_completion_record.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';
import 'package:supanotes/features/tasks/domain/task_schedule_identity.dart';
import 'package:super_editor/super_editor.dart';

final class NoteTaskCompletion {
  const NoteTaskCompletion({required this.node, required this.result});

  final TaskNode node;
  final TaskCompletionResult result;
}

/// A task block's editable state, independent of the editor's node type.
typedef NoteTaskState = ({bool isComplete, Map<String, dynamic> metadata});

/// Applies task-domain transitions to a note block and returns a new block.
///
/// Metadata is an edge representation of the task domain. Keeping its parsing
/// and serialization here leaves the application controller responsible only
/// for dispatching the resulting document command.
final class NoteTaskEditorCommands {
  const NoteTaskEditorCommands({DateTime Function()? clock}) : _clock = clock;

  final DateTime Function()? _clock;

  NoteTaskCompletion complete(
    TaskNode node, {
    DateTime? now,
    DateTime? scheduledAt,
  }) {
    final (state, result) = completeState(
      (isComplete: node.isComplete, metadata: node.metadata),
      now: now,
      scheduledAt: scheduledAt,
    );
    return NoteTaskCompletion(
      node: node.copyTaskWith(
        isComplete: state.isComplete,
        metadata: state.metadata,
      ),
      result: result,
    );
  }

  /// Completes the current occurrence of a task in [state].
  (NoteTaskState, TaskCompletionResult) completeState(
    NoteTaskState state, {
    DateTime? now,
    DateTime? scheduledAt,
  }) {
    final node = state;
    final hasTime = node.metadata['hasTime'] as bool? ?? false;
    final result =
        TaskCompletionCommand(
          () => now ?? _clock?.call() ?? DateTime.now(),
        ).complete(
          TaskSnapshot(
            dueDate: parseScheduledAt(
              node.metadata['dueDate'] as String?,
              hasTime: hasTime,
            ),
            hasTime: hasTime,
            recurrence: TaskRecurrence.parse(
              node.metadata['recurrenceRule'] as String?,
            ),
            completions: readScheduledCompletions(
              node.metadata['completions'],
              hasTime: hasTime,
            ),
          ),
          scheduledAt: scheduledAt,
        );

    final metadata = Map<String, dynamic>.from(node.metadata);
    if (result.completed) {
      metadata['lastCompletedAt'] = result.completedAt
          .toUtc()
          .toIso8601String();
    } else if (result.scheduledAt != null) {
      final completions = _completions(metadata);
      final key = scheduledAtKey(result.scheduledAt!, hasTime: hasTime);
      completions.removeWhere((rawKey, _) {
        final parsed = DateTime.tryParse(rawKey);
        return parsed != null &&
            sameScheduledAt(parsed, result.scheduledAt!, hasTime: hasTime);
      });
      completions[key] = result.completedAt.toUtc().toIso8601String();
      metadata['completions'] = completions;
    }

    return ((isComplete: result.completed, metadata: metadata), result);
  }

  TaskNode reopen(
    TaskNode node, {
    DateTime? previousDue,
    DateTime? scheduledAt,
  }) {
    final state = reopenState(
      (isComplete: node.isComplete, metadata: node.metadata),
      previousDue: previousDue,
      scheduledAt: scheduledAt,
    );
    return node.copyTaskWith(isComplete: false, metadata: state.metadata);
  }

  /// Reopens a task (or one occurrence of a recurring task) in [state].
  NoteTaskState reopenState(
    NoteTaskState node, {
    DateTime? previousDue,
    DateTime? scheduledAt,
  }) {
    final hasTime = node.metadata['hasTime'] as bool? ?? false;
    final metadata = Map<String, dynamic>.from(node.metadata);
    if (scheduledAt == null && previousDue != null) {
      metadata['dueDate'] = scheduledAtKey(previousDue, hasTime: hasTime);
    }
    if (scheduledAt != null) {
      final completions = _completions(metadata);
      completions.removeWhere((rawKey, _) {
        final parsed = DateTime.tryParse(rawKey);
        return parsed != null &&
            sameScheduledAt(parsed, scheduledAt, hasTime: hasTime);
      });
      metadata['completions'] = completions;
    }
    metadata.remove('lastCompletedAt');
    return (isComplete: false, metadata: metadata);
  }

  TaskNode updateMetadata(
    TaskNode node, {
    DateTime? dueDate,
    String? recurrence,
    bool clearDueDate = false,
    bool clearRecurrence = false,
    bool? hasTime,
    String? reminder,
    bool clearReminder = false,
  }) {
    final state = updateMetadataState(
      (isComplete: node.isComplete, metadata: node.metadata),
      dueDate: dueDate,
      recurrence: recurrence,
      clearDueDate: clearDueDate,
      clearRecurrence: clearRecurrence,
      hasTime: hasTime,
      reminder: reminder,
      clearReminder: clearReminder,
    );
    if (state == null) return node;
    return node.copyTaskWith(
      isComplete: state.isComplete,
      metadata: state.metadata,
    );
  }

  /// Changes a task's schedule or reminder in [node]; `null` when nothing
  /// changes. A schedule change archives completions and reopens the task.
  NoteTaskState? updateMetadataState(
    NoteTaskState node, {
    DateTime? dueDate,
    String? recurrence,
    bool clearDueDate = false,
    bool clearRecurrence = false,
    bool? hasTime,
    String? reminder,
    bool clearReminder = false,
  }) {
    final metadata = Map<String, dynamic>.from(node.metadata);
    final previousRecurrence = node.metadata['recurrenceRule'] as String?;
    final previousHasTime = node.metadata['hasTime'] as bool? ?? false;
    final previousDueDate = parseScheduledAt(
      node.metadata['dueDate'] as String?,
      hasTime: previousHasTime,
    );
    final previousReminder = node.metadata['reminder'] as String?;
    final nextDueDate = clearDueDate ? null : dueDate ?? previousDueDate;
    final nextRecurrence = clearRecurrence
        ? null
        : recurrence ?? previousRecurrence;
    final nextHasTime = hasTime ?? previousHasTime;
    final nextReminder = clearReminder ? null : reminder ?? previousReminder;
    final dueDateChanged = previousDueDate == null
        ? nextDueDate != null
        : nextDueDate == null ||
              !sameScheduledAt(
                previousDueDate,
                nextDueDate,
                hasTime: nextHasTime,
              );
    final scheduleChanged =
        dueDateChanged ||
        nextRecurrence != previousRecurrence ||
        nextHasTime != previousHasTime;
    if (nextReminder == previousReminder && !scheduleChanged) return null;

    if (clearDueDate) {
      metadata.remove('dueDate');
      metadata.remove('hasTime');
    } else if (dueDate != null) {
      metadata['dueDate'] = scheduledAtKey(dueDate, hasTime: nextHasTime);
    }
    if (clearRecurrence) {
      metadata.remove('recurrenceRule');
    } else if (recurrence != null) {
      metadata['recurrenceRule'] = recurrence;
    }
    if (hasTime != null) metadata['hasTime'] = hasTime;
    if (clearReminder) {
      metadata.remove('reminder');
    } else if (reminder != null) {
      metadata['reminder'] = reminder;
    }
    if (scheduleChanged) {
      final lastCompletedAt = metadata['lastCompletedAt'] is String
          ? DateTime.tryParse(metadata['lastCompletedAt'] as String)
          : null;
      metadata['completionHistory'] = archiveTaskCompletionHistory(
        history: parseTaskCompletionHistory(metadata['completionHistory']),
        completions: _completions(metadata),
        scheduledAt: previousDueDate,
        hasTime: previousHasTime,
        isCompleted: node.isComplete,
        lastCompletedAt: lastCompletedAt,
      ).map((record) => record.toJson()).toList(growable: false);
      metadata.remove('completions');
      metadata.remove('lastCompletedAt');
    }
    return (
      isComplete: scheduleChanged ? false : node.isComplete,
      metadata: metadata,
    );
  }

  Map<String, dynamic> _completions(Map<String, dynamic> metadata) =>
      Map<String, dynamic>.from(metadata['completions'] as Map? ?? {});
}
