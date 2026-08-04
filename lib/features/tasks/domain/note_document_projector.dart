import 'package:supanotes/features/notes/editor/document/note_document_codec.dart';

import 'projected_document.dart';
import 'projected_task.dart';

/// Calculates the local projections of the canonical REST/OT document.
///
/// This class has no database or editor lifecycle. Persistence belongs to
/// [TaskProjectionEngine].
class NoteDocumentProjector {
  const NoteDocumentProjector({
    NoteDocumentCodec codec = const NoteDocumentCodec(),
  }) : _codec = codec;

  final NoteDocumentCodec _codec;

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
      projectedTasks.add(
        ProjectedTask(
          id: blockData['id'] as String? ?? '',
          noteId: noteId,
          title: plain,
          isCompleted: metadata['isCompleted'] as bool? ?? false,
          dueDate: metadata['dueDate'] as String?,
          recurrenceRule:
              metadata['recurrenceRule'] as String? ??
              metadata['recurrence'] as String?,
          hasTime: metadata['hasTime'] as bool? ?? false,
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
