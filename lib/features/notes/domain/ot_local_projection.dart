import 'package:drift/drift.dart';
import 'package:super_editor/super_editor.dart';

import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';

class OtLocalProjection {
  OtLocalProjection({required AppDatabase database, required this.userId})
    : _database = database;

  final AppDatabase _database;
  final String userId;

  Future<void> project(String noteId, MutableDocument document) {
    return _database.transaction(() async {
      final now = DateTime.now().toUtc();
      final content = document
          .whereType<TextNode>()
          .map((node) => node.text.toPlainText())
          .join('\n');
      await (_database.update(
        _database.notes,
      )..where((note) => note.id.equals(noteId))).write(
        NotesCompanion(
          content: Value(content),
          excerpt: Value(content.isEmpty ? null : content),
          updatedAt: Value(now),
        ),
      );

      final existing = await (_database.select(
        _database.tasks,
      )..where((task) => task.noteId.equals(noteId))).get();
      final existingById = {for (final task in existing) task.id: task};
      final projectedIds = <String>{};

      for (var index = 0; index < document.nodeCount; index++) {
        final node = document.getNodeAt(index);
        if (node is! TaskNode) continue;
        projectedIds.add(node.id);
        final old = existingById[node.id];
        final dueDate = DateTime.tryParse(
          node.metadata['dueDate'] as String? ?? '',
        );
        final recurrence = TaskRecurrence.parse(
          node.metadata['recurrenceRule'] as String? ??
              node.metadata['recurrence'] as String?,
        );
        await _database
            .into(_database.tasks)
            .insertOnConflictUpdate(
              TaskData(
                id: node.id,
                userId: old?.userId ?? userId,
                noteId: noteId,
                title: node.text.toPlainText(),
                status: node.isComplete ? 'done' : 'open',
                position: index.toString(),
                dueDate: dueDate,
                hasTime: node.metadata['hasTime'] as bool? ?? false,
                reminder: node.metadata['reminder'] as String?,
                recurrence: recurrence,
                completedAt: node.isComplete ? old?.completedAt ?? now : null,
                createdAt: old?.createdAt ?? now,
                updatedAt: now,
                deletedAt: null,
              ),
            );
      }

      for (final task in existing) {
        if (!projectedIds.contains(task.id)) {
          await (_database.delete(
            _database.tasks,
          )..where((candidate) => candidate.id.equals(task.id))).go();
        }
      }
    });
  }
}
