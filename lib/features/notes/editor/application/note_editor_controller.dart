import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mime/mime.dart';
import 'package:supanotes/features/notes/attachments/domain/attachment_upload.dart';
import 'package:supanotes/features/notes/editor/document/attachment_nodes.dart';
import 'package:supanotes/features/notes/editor/document/empty_task_deletion_policy.dart';
import 'package:supanotes/features/notes/editor/document/hidden_task_editing_guard.dart';
import 'package:supanotes/features/notes/editor/document/note_document_constants.dart';
import 'package:supanotes/features/notes/editor/document/note_editor_commands.dart'
    show RandomDividerConversionReaction;
import 'package:supanotes/features/notes/editor/document/note_task_editor_commands.dart';
import 'package:supanotes/features/tasks/domain/task_completion_command.dart';
import 'package:super_editor/super_editor.dart';

class NoteEditorController extends ChangeNotifier {
  NoteEditorController({
    required this.userId,
    required String noteId,
    List<DocumentNode>? nodes,
  }) : _noteId = noteId,
       document = MutableDocument(
         nodes: List<DocumentNode>.of(
           nodes == null || nodes.isEmpty
               ? [ParagraphNode(id: initialNoteBlockId, text: AttributedText())]
               : nodes,
         ),
       ) {
    _setupEditor();
  }

  final String userId;
  final MutableDocument document;
  late final Editor editor;
  late final MutableDocumentComposer composer;
  final FocusNode focusNode = FocusNode();
  void Function(bool)? onHasContentChanged;
  void Function()? _assertCanMutate;
  late final HiddenTaskEditingGuard _hiddenTaskEditingGuard;
  final String _noteId;
  var _disposed = false;

  void attachMutationGuard(void Function() assertCanMutate) {
    _assertCanMutate = assertCanMutate;
  }

  void setHiddenTaskPredicate(bool Function(TaskNode node) predicate) {
    _hiddenTaskEditingGuard.updateHiddenTaskPredicate(predicate);
    final selection = composer.selection;
    if (selection == null) return;

    if (_hiddenTaskEditingGuard.selectionTouchesHiddenTask(
      document,
      selection,
    )) {
      composer.clearSelection();
    }
  }

  TaskCompletionResult? completeTaskInEditor(
    String nodeId, {
    DateTime? now,
    DateTime? scheduledAt,
  }) {
    _assertCanMutate?.call();
    final node = document.getNodeById(nodeId);
    if (node is! TaskNode) return null;
    final mutation = const NoteTaskEditorCommands().complete(
      node,
      now: now,
      scheduledAt: scheduledAt,
    );
    editor.execute([
      ReplaceNodeRequest(existingNodeId: nodeId, newNode: mutation.node),
    ]);
    return mutation.result;
  }

  void reopenTaskInEditor(
    String nodeId, {
    DateTime? previousDue,
    DateTime? scheduledAt,
  }) {
    _assertCanMutate?.call();
    final node = document.getNodeById(nodeId);
    if (node is! TaskNode) return;
    final updatedNode = const NoteTaskEditorCommands().reopen(
      node,
      previousDue: previousDue,
      scheduledAt: scheduledAt,
    );
    editor.execute([
      ReplaceNodeRequest(existingNodeId: nodeId, newNode: updatedNode),
    ]);
  }

  void updateTaskMetadataInEditor(
    String nodeId, {
    DateTime? dueDate,
    String? recurrence,
    bool clearDueDate = false,
    bool clearRecurrence = false,
    bool? hasTime,
    String? reminder,
    bool clearReminder = false,
  }) {
    _assertCanMutate?.call();
    final node = document.getNodeById(nodeId);
    if (node is! TaskNode) return;
    final updatedNode = const NoteTaskEditorCommands().updateMetadata(
      node,
      dueDate: dueDate,
      recurrence: recurrence,
      clearDueDate: clearDueDate,
      clearRecurrence: clearRecurrence,
      hasTime: hasTime,
      reminder: reminder,
      clearReminder: clearReminder,
    );
    if (identical(updatedNode, node)) return;
    editor.execute([
      ReplaceNodeRequest(existingNodeId: nodeId, newNode: updatedNode),
    ]);
  }

  void _setupEditor() {
    composer = MutableDocumentComposer();
    _hiddenTaskEditingGuard = HiddenTaskEditingGuard();
    editor = createDefaultDocumentEditor(
      document: document,
      composer: composer,
    );
    editor.requestHandlers.insertAll(0, [
      _hiddenTaskEditingGuard.handle,
      handleEmptyTaskDeletion,
    ]);
    editor.reactionPipeline.removeWhere(
      (r) => r is HorizontalRuleConversionReaction,
    );
    editor.reactionPipeline.add(
      const RandomDividerConversionReaction(),
    );
    document.addListener(_clearSelectionIfHidden);
  }

  void _clearSelectionIfHidden(DocumentChangeLog _) {
    final selection = composer.selection;
    if (selection == null ||
        !_hiddenTaskEditingGuard.selectionTouchesHiddenTask(
          document,
          selection,
        )) {
      return;
    }
    composer.clearSelection();
    focusNode.unfocus();
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

  Future<AttachmentUploadResult> attachFileFromPath({
    required String filePath,
    required String mimeType,
    required AttachmentUploader uploader,
  }) {
    _assertCanMutate?.call();
    final id = Editor.createNodeId();
    editor.execute([
      InsertNodeAtCaretRequest(node: DocumentAttachmentNode(id: id)),
    ]);

    return uploader
        .upload(
          id: id,
          noteId: _noteId,
          file: File(filePath),
          mimeType: mimeType,
        )
        .then((result) {
          if (_disposed) return result;
          final node = document.getNodeById(id);
          if (node is DocumentAttachmentNode) {
            editor.execute([
              ReplaceNodeRequest(
                existingNodeId: id,
                newNode: node.copyWithAddedMetadata({
                  'filename': result.fileName,
                  'fileSize': result.fileSize,
                  'mimeType': result.mimeType,
                  'url': result.downloadUrl,
                }),
              ),
            ]);
          }
          return result;
        })
        .catchError((Object error, StackTrace stackTrace) {
          if (!_disposed && document.getNodeById(id) != null) {
            try {
              _assertCanMutate?.call();
              editor.execute([DeleteNodeRequest(nodeId: id)]);
            } on StateError {
              // The session was closed; its document must not be mutated.
            }
          }
          Error.throwWithStackTrace(error, stackTrace);
        });
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    onHasContentChanged = null;
    document.removeListener(_clearSelectionIfHidden);
    editor.dispose();
    document.dispose();
    composer.dispose();
    focusNode.dispose();
    super.dispose();
  }
}
