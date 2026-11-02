import 'dart:io';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:mime/mime.dart';
import 'package:supanotes/features/notes/attachments/domain/attachment_upload.dart';
import 'package:supanotes/features/notes/editor/appflowy/note_appflowy_codec.dart';
import 'package:supanotes/features/notes/editor/appflowy/note_editor_state.dart';
import 'package:supanotes/features/notes/editor/appflowy/note_format_commands.dart';
import 'package:supanotes/features/notes/editor/appflowy/note_task_commands.dart';
import 'package:supanotes/features/notes/editor/document/note_blocks.dart';
import 'package:supanotes/features/notes/editor/document/note_document_constants.dart';
import 'package:supanotes/features/tasks/domain/task_completion_command.dart';
import 'package:supanotes/features/tasks/presentation/controllers/task_metadata_draft.dart';
import 'package:uuid/uuid.dart';

/// Owns one open note's editor state and the edits the app makes to it
/// (tasks, attachments) besides typing.
class NoteEditorController {
  NoteEditorController({
    required this.userId,
    required String noteId,
    List<NoteBlock>? blocks,
  }) : _noteId = noteId,
       editorState = NoteEditorState(
         document: const NoteAppFlowyCodec().toDocument(
           blocks == null || blocks.isEmpty
               ? [NoteBlock(id: initialNoteBlockId, type: 'paragraph')]
               : blocks,
         ),
       );

  final String userId;
  final NoteEditorState editorState;
  final FocusNode focusNode = FocusNode(debugLabel: 'note editor');
  final String _noteId;
  void Function()? _assertCanMutate;
  var _disposed = false;

  static const _uuid = Uuid();

  /// Called before every app-initiated edit; throws when the note became
  /// read-only.
  void attachMutationGuard(void Function() assertCanMutate) {
    _assertCanMutate = assertCanMutate;
  }

  /// Whether completed tasks are hidden (and therefore not editable).
  set hideCompleted(bool value) => editorState.hideCompleted = value;

  /// The task block [blockId], as the metadata sheet edits it.
  TaskMetadataDraft? taskMetadata(String blockId) {
    final node = editorState.nodeForBlock(blockId);
    if (node?.type != TodoListBlockKeys.type) return null;
    return TaskMetadataDraft.fromMetadata(
      Map<String, dynamic>.from(
        node!.attributes[NoteNodeKeys.metadata] as Map? ?? const {},
      ),
    );
  }

  /// Whether the note has a task block [blockId].
  bool hasTask(String blockId) =>
      editorState.nodeForBlock(blockId)?.type == TodoListBlockKeys.type;

  /// Puts the caret at the start of block [blockId].
  void focusBlock(String blockId) {
    final node = editorState.nodeForBlock(blockId);
    if (node == null) return;
    editorState.selection = Selection.collapsed(Position(path: node.path));
  }

  Future<TaskCompletionResult?> completeTaskInEditor(
    String blockId, {
    DateTime? now,
    DateTime? scheduledAt,
  }) {
    _assertCanMutate?.call();
    return editorState.completeNoteTask(
      blockId,
      now: now,
      scheduledAt: scheduledAt,
    );
  }

  Future<void> reopenTaskInEditor(
    String blockId, {
    DateTime? previousDue,
    DateTime? scheduledAt,
  }) {
    _assertCanMutate?.call();
    return editorState.reopenNoteTask(
      blockId,
      previousDue: previousDue,
      scheduledAt: scheduledAt,
    );
  }

  /// Deletes a task block, keeping one editable block in the note.
  Future<void> deleteTaskInEditor(String blockId) {
    _assertCanMutate?.call();
    final node = editorState.nodeForBlock(blockId);
    if (node == null || node.type != TodoListBlockKeys.type) {
      return Future.value();
    }
    final transaction = editorState.transaction;
    if (editorState.document.root.children.length == 1 &&
        node.parent == editorState.document.root) {
      transaction.insertNode(
        node.path,
        paragraphNode(attributes: {NoteNodeKeys.blockId: blockId}),
      );
    }
    transaction.deleteNode(node);
    return editorState.apply(transaction, withUpdateSelection: false);
  }

  Future<void> updateTaskMetadataInEditor(
    String blockId, {
    DateTime? dueDate,
    String? recurrence,
    bool clearDueDate = false,
    bool clearRecurrence = false,
    bool? hasTime,
    String? reminder,
    bool clearReminder = false,
  }) {
    _assertCanMutate?.call();
    return editorState.updateNoteTaskMetadata(
      blockId,
      dueDate: dueDate,
      recurrence: recurrence,
      clearDueDate: clearDueDate,
      clearRecurrence: clearRecurrence,
      hasTime: hasTime,
      reminder: reminder,
      clearReminder: clearReminder,
    );
  }

  Future<void> pickAndAttachFile({
    required AttachmentUploader uploader,
    bool imageOnly = false,
  }) async {
    _assertCanMutate?.call();
    final result = await FilePicker.platform.pickFiles(
      type: imageOnly ? FileType.image : FileType.any,
    );
    if (result == null || result.files.isEmpty) return;

    final path = result.files.single.path;
    if (path == null) return;
    await attachFileFromPath(
      filePath: path,
      mimeType: lookupMimeType(path) ?? 'application/octet-stream',
      uploader: uploader,
    );
  }

  /// Inserts an attachment block at the caret right away, then fills in its
  /// file details once [uploader] finishes; a failed upload removes it.
  Future<AttachmentUploadResult> attachFileFromPath({
    required String filePath,
    required String mimeType,
    required AttachmentUploader uploader,
  }) async {
    _assertCanMutate?.call();
    final id = _uuid.v4();
    await editorState.insertNoteBlockAtCaret(
      NoteBlock(id: id, type: 'attachment'),
    );
    try {
      final result = await uploader.upload(
        id: id,
        noteId: _noteId,
        file: File(filePath),
        mimeType: mimeType,
      );
      final node = _disposed ? null : editorState.nodeForBlock(id);
      if (node != null) {
        await editorState.apply(
          editorState.transaction..updateNode(node, {
            NoteNodeKeys.metadata: {
              ...?(node.attributes[NoteNodeKeys.metadata] as Map?)
                  ?.cast<String, dynamic>(),
              'filename': result.fileName,
              'fileSize': result.fileSize,
              'mimeType': result.mimeType,
              'url': result.downloadUrl,
            },
          }),
          withUpdateSelection: false,
        );
      }
      return result;
    } catch (_) {
      final node = _disposed ? null : editorState.nodeForBlock(id);
      if (node != null) {
        try {
          _assertCanMutate?.call();
          await editorState.apply(
            editorState.transaction..deleteNode(node),
            withUpdateSelection: false,
          );
        } on StateError {
          // The session was closed; its document must not be mutated.
        }
      }
      rethrow;
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    editorState.dispose();
    focusNode.dispose();
  }
}
