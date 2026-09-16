import 'dart:convert';

import 'package:supanotes/features/notes/editor/document/note_document_codec.dart';
import 'package:supanotes/features/tasks/domain/task_notification_entry.dart';
import 'package:supanotes/features/tasks/domain/task_notification_time.dart';
import 'package:supanotes/features/tasks/domain/task_occurrence.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';
import 'package:supanotes/features/tasks/domain/task_schedule_identity.dart';

/// Parsed, persistence-free representation of one task block.
///
/// This is deliberately shared by the notification and list readers. The
/// readers still choose different occurrence policies: notifications may
/// advance an overdue recurring task to a future reminder, while lists keep
/// the current visible occurrence.
class ParsedNoteTask {
  const ParsedNoteTask({
    required this.blockId,
    required this.title,
    required this.dueDate,
    required this.hasTime,
    required this.recurrence,
    required this.reminder,
    required this.completions,
    required this.isCompleted,
    required this.lastCompletedAt,
  });

  final String blockId;
  final String title;
  final DateTime? dueDate;
  final bool hasTime;
  final TaskRecurrence? recurrence;
  final String? reminder;
  final Map<DateTime, DateTime> completions;
  final bool isCompleted;
  final DateTime? lastCompletedAt;
}

/// Decodes task blocks from an effective document snapshot.
///
/// [NoteDocumentCodec] remains the authority for document and metadata
/// validation. Invalid snapshots are allowed to throw so callers can expose
/// the error instead of silently hiding one note from a task list.
List<ParsedNoteTask> parseNoteTaskBlocks(String documentJson) {
  final json = jsonDecode(documentJson) as Map<String, dynamic>;
  final snapshot = const NoteDocumentCodec().parseSnapshot(
    json,
    allowEmptyDeltaOperations: true,
    allowMutationDeltaOperations: true,
  );
  return [
    for (final block in snapshot.blocks)
      if (block.type == 'task')
        _parseNoteTaskBlock(block.id, block.text, block.metadata),
  ];
}

ParsedNoteTask _parseNoteTaskBlock(
  String blockId,
  String title,
  Map<String, dynamic> metadata,
) {
  final hasTime = metadata['hasTime'] as bool? ?? false;
  return ParsedNoteTask(
    blockId: blockId,
    title: title,
    hasTime: hasTime,
    dueDate: parseScheduledAt(
      metadata['dueDate'] as String?,
      hasTime: hasTime,
    ),
    recurrence: TaskRecurrence.parse(
      metadata['recurrenceRule'] as String?,
    ),
    reminder: metadata['reminder'] as String?,
    completions: readScheduledCompletions(
      metadata['completions'],
      hasTime: hasTime,
    ),
    isCompleted: metadata['isCompleted'] as bool? ?? false,
    lastCompletedAt: _parseCompletedAt(metadata['lastCompletedAt']),
  );
}

DateTime? _parseCompletedAt(Object? value) {
  if (value is! String) return null;
  return DateTime.tryParse(value)?.toUtc();
}

class NoteTaskReader {
  const NoteTaskReader({this.clock});

  final DateTime Function()? clock;

  List<TaskNotificationEntry> read(String documentJson, {String? noteId}) {
    final policy = TaskOccurrencePolicy(clock: clock);
    final entries = <TaskNotificationEntry>[];
    for (final task in parseNoteTaskBlocks(documentJson)) {
      final occurrence = policy.resolveNotificationOccurrence(
        taskId: task.blockId,
        anchor: task.dueDate,
        recurrence: task.recurrence,
        hasTime: task.hasTime,
        completedAtByScheduledAt: task.completions,
        notificationAt: task.reminder == null
            ? null
            : (scheduledAt) => computeTaskNotificationTime(
                due: scheduledAt,
                hasTime: task.hasTime,
                reminder: task.reminder,
              ),
      );
      if (occurrence == null || occurrence.isCompleted) continue;
      if (task.isCompleted && task.recurrence == null) continue;
      entries.add(
        TaskNotificationEntry(
          id: task.blockId,
          title: task.title,
          dueDate: occurrence.scheduledAt,
          hasTime: task.hasTime,
          reminder: task.reminder,
          source: TaskNotificationEntrySource.note,
          noteId: noteId,
        ),
      );
    }
    return entries;
  }
}
