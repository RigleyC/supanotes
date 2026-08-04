import 'package:super_editor/super_editor.dart';

import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/features/notes/editor/document/note_document_codec.dart';
import 'note_document_projector.dart';
import 'projected_document.dart';

class TaskProjectionEngine {
  final AppDatabase _database;
  final NoteDocumentCodec _codec;
  final NoteDocumentProjector _projector;

  TaskProjectionEngine({
    required AppDatabase database,
    NoteDocumentCodec codec = const NoteDocumentCodec(),
    DateTime Function()? now,
  }) : _database = database,
       _codec = codec,
       _projector = NoteDocumentProjector(codec: codec, now: now);

  /// Projects tasks and note content from canonical REST/OT blocks into SQLite inside a single atomic transaction.
  Future<void> projectTasksFromBlocks({
    required String noteId,
    required List<dynamic> blocks,
    String userId = '',
  }) async {
    final projection = _projector.projectBlocks(noteId: noteId, blocks: blocks);

    await _saveProjection(
      noteId: noteId,
      projection: projection,
      userId: userId,
    );
  }

  /// Projects tasks from a canonical REST/OT document snapshot.
  Future<void> projectTasksFromSnapshot({
    required String noteId,
    required Map<String, dynamic> snapshot,
    String userId = '',
  }) async {
    final projection = _projector.projectSnapshot(
      noteId: noteId,
      snapshot: snapshot,
    );
    await _saveProjection(
      noteId: noteId,
      projection: projection,
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
    final projection = _projector.projectBlocks(noteId: noteId, blocks: blocks);
    await _saveProjection(
      noteId: noteId,
      projection: projection,
      userId: userId,
    );
  }

  Future<void> _saveProjection({
    required String noteId,
    required ProjectedDocument projection,
    required String userId,
  }) {
    return _database.saveProjectedDocument(
      noteId: noteId,
      content: projection.content,
      excerpt: projection.excerpt,
      tasks: projection.tasks,
      userId: userId,
    );
  }
}
