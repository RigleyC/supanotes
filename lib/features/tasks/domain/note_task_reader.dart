import 'dart:convert';

import 'package:supanotes/features/notes/editor/document/note_document_codec.dart';

import 'task_occurrence.dart';
import 'task_recurrence.dart';
import 'task_schedule_identity.dart';
import 'task_notification_entry.dart';
import 'task_notification_time.dart';

class NoteTaskReader {
  const NoteTaskReader({this.clock});

  final DateTime Function()? clock;

  List<TaskNotificationEntry> read(String documentJson) {
    final json = jsonDecode(documentJson) as Map<String, dynamic>;
    final snapshot = const NoteDocumentCodec().parseSnapshot(
      json,
      allowEmptyDeltaOperations: true,
      allowMutationDeltaOperations: true,
    );
    final policy = TaskOccurrencePolicy(clock: clock);
    final entries = <TaskNotificationEntry>[];
    for (final block in snapshot.blocks) {
      if (block.type != 'task') continue;
      final metadata = block.metadata;
      final hasTime = metadata['hasTime'] as bool? ?? false;
      final dueDate = parseScheduledAt(
        metadata['dueDate'] as String?,
        hasTime: hasTime,
      );
      final recurrence = TaskRecurrence.parse(
        metadata['recurrenceRule'] as String?,
      );
      final reminder = metadata['reminder'] as String?;
      final completions = readScheduledCompletions(
        metadata['completions'],
        hasTime: hasTime,
      );
      final occurrence = policy.resolveNotificationOccurrence(
        taskId: block.id,
        anchor: dueDate,
        recurrence: recurrence,
        hasTime: hasTime,
        completedAtByScheduledAt: completions,
        notificationAt: reminder == null
            ? null
            : (scheduledAt) => computeTaskNotificationTime(
                due: scheduledAt,
                hasTime: hasTime,
                reminder: reminder,
              ),
      );
      if (occurrence == null || occurrence.isCompleted) continue;
      if (metadata['isCompleted'] == true && recurrence == null) continue;
      entries.add(
        TaskNotificationEntry(
          id: block.id,
          title: block.text,
          dueDate: occurrence.scheduledAt,
          hasTime: hasTime,
          reminder: reminder,
        ),
      );
    }
    return entries;
  }
}
