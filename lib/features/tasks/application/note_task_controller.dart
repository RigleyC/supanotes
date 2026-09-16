import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/features/notes/editor/application/note_editor_provider.dart';
import 'package:supanotes/features/notes/editor/application/note_editor_session.dart';
import 'package:supanotes/features/tasks/domain/task_list_item.dart';

/// Resolves the shared editor session that owns a note document.
typedef NoteEditorSessionReader =
    Future<NoteEditorSession> Function(
      String noteId,
    );

/// Owns mutations for tasks that live inside a note document.
///
/// A note task must never be written through the standalone task repository.
/// This small application service keeps that ownership explicit while still
/// allowing the global task list to trigger the canonical editor operation.
class NoteTaskController {
  /// Creates a controller backed by the note-session resolver.
  const NoteTaskController(this._readSession);

  final NoteEditorSessionReader _readSession;

  /// Completes the requested occurrence through a canonical document
  /// operation and makes that operation durable locally.
  Future<void> complete(
    NoteTask task, {
    DateTime? scheduledAt,
  }) async {
    final session = await _readSession(task.noteId);
    if (!session.captureLocalOperations) {
      throw StateError('Esta nota não permite concluir a tarefa.');
    }

    final result = session.controller.completeTaskInEditor(
      task.blockId,
      scheduledAt: scheduledAt,
    );
    if (result == null) {
      throw StateError('A tarefa não está mais disponível nesta nota.');
    }

    // Make the document operation durable before reporting success to the
    // list. Remote acknowledgement remains the responsibility of the note
    // outbox/session worker.
    await session.flushNow();
  }
}

/// Provides note-owned task mutations to the global task list.
final Provider<NoteTaskController> noteTaskControllerProvider =
    Provider.autoDispose<NoteTaskController>(
      (ref) => NoteTaskController(
        (noteId) => ref.read(noteEditorSessionProvider(noteId).future),
      ),
    );
