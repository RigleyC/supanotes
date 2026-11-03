import 'dart:async';
import 'dart:io';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:mime/mime.dart';
import 'package:supanotes/features/notes/attachments/domain/attachment_upload.dart';
import 'package:supanotes/features/notes/editor/appflowy/note_appflowy_codec.dart';
import 'package:supanotes/features/notes/editor/appflowy/note_block_visibility.dart';
import 'package:supanotes/features/notes/editor/appflowy/note_format_commands.dart';
import 'package:supanotes/features/notes/editor/appflowy/note_task_commands.dart';
import 'package:supanotes/features/notes/editor/document/note_blocks.dart';
import 'package:supanotes/features/notes/editor/document/note_document_constants.dart';
import 'package:supanotes/features/notes/editor/document/note_task_editor_commands.dart';
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
       editorState = EditorState(
         document: const NoteAppFlowyCodec().toDocument(
           blocks == null || blocks.isEmpty
               ? [NoteBlock(id: initialNoteBlockId, type: 'paragraph')]
               : blocks,
         ),
       ) {
    editorState.selectionNotifier.addListener(_updateEditing);
    focusNode.addListener(_updateEditing);
  }

  final String userId;
  final EditorState editorState;
  final FocusNode focusNode = FocusNode(debugLabel: 'note editor');

  /// The user is editing: the editor has focus and shows a caret or a
  /// selection. A caret placed by code alone (a deep link, a remote change)
  /// is not editing, so the toolbar and keyboard controls stay hidden.
  final ValueNotifier<bool> editing = ValueNotifier(false);

  void _updateEditing() {
    if (_disposed) return;
    editing.value = editorState.selection != null && focusNode.hasFocus;
  }

  /// Places the caret as a user tap would: the editor takes focus and the
  /// keyboard opens.
  void editAt(Selection selection) => editorState.updateSelectionWithReason(
    selection,
    reason: SelectionUpdateReason.uiEvent,
  );
  final String _noteId;
  void Function()? _assertCanMutate;
  var _disposed = false;

  static const _uuid = Uuid();

  /// Called before every app-initiated edit; throws when the note became
  /// read-only.
  void attachMutationGuard(void Function() assertCanMutate) {
    _assertCanMutate = assertCanMutate;
  }

  NoteBlockVisibility? _visibility;
  bool _hideCompleted = false;

  /// Connects the session that knows the whole note, including the blocks
  /// the editor leaves out.
  void attachVisibility(NoteBlockVisibility visibility) {
    _visibility = visibility;
    if (_hideCompleted) unawaited(visibility.hideBlocks(isCompletedTaskBlock));
  }

  /// Leaves completed tasks out of the editor (they stay in the note).
  set hideCompleted(bool value) {
    if (_hideCompleted == value) return;
    _hideCompleted = value;
    unawaited(_visibility?.hideBlocks(value ? isCompletedTaskBlock : null));
  }

  /// Hides tasks completed since the last check, once their exit animation
  /// has played.
  Future<void> refreshHidden() async => _visibility?.refreshHidden();

  NoteBlock? _hiddenTask(String blockId) {
    final block = _visibility?.hiddenBlock(blockId);
    return block?.type == 'task' ? block : null;
  }

  /// The task block [blockId], as the metadata sheet edits it.
  TaskMetadataDraft? taskMetadata(String blockId) {
    final node = editorState.nodeForBlock(blockId);
    if (node?.type == TodoListBlockKeys.type) {
      return TaskMetadataDraft.fromMetadata(
        Map<String, dynamic>.from(
          node!.attributes[NoteNodeKeys.metadata] as Map? ?? const {},
        ),
      );
    }
    final hidden = _hiddenTask(blockId);
    return hidden == null
        ? null
        : TaskMetadataDraft.fromMetadata(taskStateOfBlock(hidden).metadata);
  }

  /// Whether the note has a task block [blockId] (shown or hidden).
  bool hasTask(String blockId) =>
      editorState.nodeForBlock(blockId)?.type == TodoListBlockKeys.type ||
      _hiddenTask(blockId) != null;

  /// Shows the caret at the start of block [blockId] without starting to
  /// edit (no focus, no keyboard), e.g. when a task is opened from a link.
  ///
  /// AppFlowy's plain `selection =` setter keeps the last update reason, a
  /// user tap by default, which would focus the editor.
  void focusBlock(String blockId) {
    final node = editorState.nodeForBlock(blockId);
    if (node == null) return;
    editorState.updateSelectionWithReason(
      Selection.collapsed(Position(path: node.path)),
      reason: SelectionUpdateReason.transaction,
    );
  }

  Future<TaskCompletionResult?> completeTaskInEditor(
    String blockId, {
    DateTime? now,
    DateTime? scheduledAt,
  }) {
    _assertCanMutate?.call();
    final hidden = _hiddenTask(blockId);
    if (hidden != null) {
      final (state, result) = const NoteTaskEditorCommands().completeState(
        taskStateOfBlock(hidden),
        now: now,
        scheduledAt: scheduledAt,
      );
      return _visibility!
          .replaceHiddenBlock(blockId, withTaskState(hidden, state))
          .then((_) => result);
    }
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
    final hidden = _hiddenTask(blockId);
    if (hidden != null) {
      final state = const NoteTaskEditorCommands().reopenState(
        taskStateOfBlock(hidden),
        previousDue: previousDue,
        scheduledAt: scheduledAt,
      );
      return _visibility!.replaceHiddenBlock(
        blockId,
        withTaskState(hidden, state),
      );
    }
    return editorState.reopenNoteTask(
      blockId,
      previousDue: previousDue,
      scheduledAt: scheduledAt,
    );
  }

  /// Deletes a task block, keeping one editable block in the note.
  Future<void> deleteTaskInEditor(String blockId) {
    _assertCanMutate?.call();
    if (_hiddenTask(blockId) != null) {
      return _visibility!.replaceHiddenBlock(blockId, null);
    }
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
    final hidden = _hiddenTask(blockId);
    if (hidden != null) {
      final state = const NoteTaskEditorCommands().updateMetadataState(
        taskStateOfBlock(hidden),
        dueDate: dueDate,
        recurrence: recurrence,
        clearDueDate: clearDueDate,
        clearRecurrence: clearRecurrence,
        hasTime: hasTime,
        reminder: reminder,
        clearReminder: clearReminder,
      );
      if (state == null) return Future.value();
      return _visibility!.replaceHiddenBlock(
        blockId,
        withTaskState(hidden, state),
      );
    }
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
    editorState.selectionNotifier.removeListener(_updateEditing);
    focusNode.removeListener(_updateEditing);
    editing.dispose();
    editorState.dispose();
    focusNode.dispose();
  }
}
