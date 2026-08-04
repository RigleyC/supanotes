import 'package:supanotes/core/utils/recurrence.dart';
import 'package:supanotes/features/notes/editor/document/note_document_codec.dart';

import 'projected_document.dart';
import 'projected_task.dart';
import 'task_recurrence.dart';

/// Calculates the local projections of the canonical REST/OT document.
///
/// This class has no database or editor lifecycle. Persistence belongs to
/// [TaskProjectionEngine].
class NoteDocumentProjector {
  const NoteDocumentProjector({
    NoteDocumentCodec codec = const NoteDocumentCodec(),
    this.now,
  }) : _codec = codec;

  final NoteDocumentCodec _codec;
  final DateTime Function()? now;

  ProjectedDocument projectBlocks({
    required String noteId,
    required List<dynamic> blocks,
  }) {
    final projectedTasks = <ProjectedTask>[];
    final textBuffer = StringBuffer();

    for (var i = 0; i < blocks.length; i++) {
      final blockData = blocks[i];
      if (blockData is! Map<String, dynamic>) continue;

      final type = blockData['type'] as String?;
      final content =
          (blockData['content'] ?? blockData['delta']) as List<dynamic>? ?? [];
      final attributedText = _codec.attributedFromDelta(content);
      final plain = attributedText.toPlainText();
      if (plain.isNotEmpty) textBuffer.writeln(plain);

      if (type != 'task') continue;

      final metadata = Map<String, dynamic>.from(
        blockData['metadata'] as Map? ?? {},
      );
      final isCompleted = metadata['isCompleted'] as bool? ?? false;
      final hasTime = metadata['hasTime'] as bool? ?? false;
      final recurrenceRule =
          metadata['recurrenceRule'] as String? ??
          metadata['recurrence'] as String?;
      final recurrence = TaskRecurrence.parse(recurrenceRule);
      final rawDueDate = DateTime.tryParse(
        metadata['dueDate'] as String? ?? '',
      );
      final currentDueDate =
          !isCompleted && rawDueDate != null && recurrence != null
          ? advanceRecurringDueDate(
              from: rawDueDate,
              recurrence: recurrence,
              hasTime: hasTime,
              now: now?.call(),
            )
          : rawDueDate;
      final rawDueDateString = metadata['dueDate'] as String?;
      final projectedDueDate = currentDueDate == rawDueDate
          ? rawDueDateString
          : currentDueDate?.toIso8601String();
      projectedTasks.add(
        ProjectedTask(
          id: blockData['id'] as String? ?? '',
          noteId: noteId,
          title: plain,
          isCompleted: isCompleted,
          dueDate: projectedDueDate,
          recurrenceRule: recurrenceRule,
          hasTime: hasTime,
          reminder: metadata['reminder'] as String?,
          position: i.toString(),
        ),
      );
    }

    final content = textBuffer.toString().trimRight();
    return ProjectedDocument(
      content: content,
      excerpt: content.isEmpty
          ? null
          : (content.length > 200 ? content.substring(0, 200) : content),
      tasks: projectedTasks,
    );
  }

  ProjectedDocument projectSnapshot({
    required String noteId,
    required Map<String, dynamic> snapshot,
  }) {
    return projectBlocks(
      noteId: noteId,
      blocks: snapshot['blocks'] as List<dynamic>? ?? [],
    );
  }
}
