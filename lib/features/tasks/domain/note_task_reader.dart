import 'dart:convert';

import 'package:supanotes/features/notes/editor/document/note_document_codec.dart';

import 'task_occurrence.dart';
import 'task_recurrence.dart';
import 'task_notification_entry.dart';

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
      final dueDate = DateTime.tryParse(metadata['dueDate'] as String? ?? '');
      final recurrence = TaskRecurrence.parse(
        metadata['recurrenceRule'] as String?,
      );
      final completions = _readCompletions(metadata['completions']);
      final occurrence = policy.resolveCurrent(
        taskId: block.id,
        anchor: dueDate,
        recurrence: recurrence,
        hasTime: metadata['hasTime'] as bool? ?? false,
        completedAtByScheduledAt: completions,
      );
      if (occurrence == null || occurrence.isCompleted) continue;
      if (metadata['isCompleted'] == true && recurrence == null) continue;
      entries.add(
        TaskNotificationEntry(
          id: block.id,
          title: block.text,
          dueDate: occurrence.scheduledAt,
          hasTime: metadata['hasTime'] as bool? ?? false,
          reminder: metadata['reminder'] as String?,
        ),
      );
    }
    return entries;
  }

  Map<DateTime, DateTime> _readCompletions(Object? value) {
    if (value is! Map) return const {};
    final result = <DateTime, DateTime>{};
    for (final entry in value.entries) {
      if (entry.key is! String || entry.value is! String) continue;
      final scheduledAt = DateTime.tryParse(entry.key as String);
      final completedAt = DateTime.tryParse(entry.value as String);
      if (scheduledAt != null && completedAt != null) {
        result[scheduledAt] = completedAt;
      }
    }
    return result;
  }
}
