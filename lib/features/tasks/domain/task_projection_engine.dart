import 'dart:async';

import 'package:super_editor/super_editor.dart';

import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/features/notes/domain/note_document_codec.dart';
import 'package:supanotes/features/tasks/domain/projected_task.dart';

class TaskProjectionEngine {
  final AppDatabase _database;
  final NoteDocumentCodec _codec;

  TaskProjectionEngine({
    required AppDatabase database,
    NoteDocumentCodec codec = const NoteDocumentCodec(),
  })  : _database = database,
        _codec = codec;

  /// Projects tasks and note content from canonical REST/OT blocks into SQLite inside a single atomic transaction.
  Future<void> projectTasksFromBlocks({
    required String noteId,
    required List<dynamic> blocks,
    String userId = '',
  }) async {
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
      if (plain.isNotEmpty) {
        textBuffer.writeln(plain);
      }

      if (type == 'task') {
        final blockId = blockData['id'] as String? ?? '';
        final metadata = Map<String, dynamic>.from(blockData['metadata'] as Map? ?? {});

        projectedTasks.add(
          ProjectedTask(
            id: blockId,
            noteId: noteId,
            title: plain,
            isCompleted: metadata['isCompleted'] as bool? ?? false,
            dueDate: metadata['dueDate'] as String?,
            recurrenceRule: metadata['recurrenceRule'] as String? ??
                metadata['recurrence'] as String?,
            hasTime: metadata['hasTime'] as bool? ?? false,
            reminder: metadata['reminder'] as String?,
            position: i.toString(),
          ),
        );
      }
    }

    final fullText = textBuffer.toString().trimRight();
    final excerpt =
        fullText.isEmpty ? null : (fullText.length > 200 ? fullText.substring(0, 200) : fullText);

    await _database.saveProjectedDocument(
      noteId: noteId,
      content: fullText,
      excerpt: excerpt,
      tasks: projectedTasks,
      userId: userId,
    );
  }

  /// Projects tasks from a canonical REST/OT document snapshot.
  Future<void> projectTasksFromSnapshot({
    required String noteId,
    required Map<String, dynamic> snapshot,
    String userId = '',
  }) async {
    final blocks = snapshot['blocks'] as List<dynamic>? ?? [];
    await projectTasksFromBlocks(
      noteId: noteId,
      blocks: blocks,
      userId: userId,
    );
  }

  /// Projects tasks directly from an active SuperEditor [MutableDocument] by converting to canonical blocks first.
  Future<void> projectTasksFromDocument({
    required String noteId,
    required MutableDocument document,
    String userId = '',
  }) async {
    final blocks = _codec.encodeDocument(document);
    await projectTasksFromBlocks(
      noteId: noteId,
      blocks: blocks,
      userId: userId,
    );
  }
}
