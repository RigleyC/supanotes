library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mime/mime.dart';
import 'package:super_editor/super_editor.dart';
import 'package:supanotes/features/notes/domain/attachment_nodes.dart';
import 'package:supanotes/features/tasks/domain/task_completion_command.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';
import 'package:supanotes/features/notes/domain/note_document_codec.dart';
import 'package:supanotes/features/notes/domain/note_editor_commands.dart'
    show RandomDividerConversionReaction;
import 'package:supanotes/shared/widgets/app_snackbar.dart';

const int _dividerCount = 35;

class NoteEditorController extends ChangeNotifier {
  NoteEditorController({
    required this.userId,
    Future<void> Function(String id, String filePath, String mimeType)?
    onUploadFile,
  }) : _onUploadFile = onUploadFile;

  final String userId;
  final Future<void> Function(String id, String filePath, String mimeType)?
  _onUploadFile;

  MutableDocument? document;
  Editor? editor;
  MutableDocumentComposer? composer;
  final FocusNode focusNode = FocusNode();
  void Function(bool)? onHasContentChanged;

  String? _noteId;

  bool get hasDocument => document != null;

  void initOtOnly({required String noteId}) {
    document = NoteDocumentCodec.documentFromNodes([]);
    _noteId = noteId;
    _setupEditor();
    notifyListeners();
  }

  TaskCompletionResult? completeTaskInEditor(
    String nodeId, {
    DateTime? now,
    DateTime? scheduledAt,
  }) {
    final node = document?.getNodeById(nodeId);
    if (node is TaskNode) {
      final dueDateStr = node.metadata['dueDate'] as String?;
      final hasTime = node.metadata['hasTime'] as bool? ?? false;
      final recurrenceStr =
          node.metadata['recurrenceRule'] as String? ??
          node.metadata['recurrence'] as String?;
      final snapshot = TaskSnapshot(
        dueDate: dueDateStr != null ? DateTime.tryParse(dueDateStr) : null,
        hasTime: hasTime,
        recurrence: TaskRecurrence.parse(recurrenceStr),
      );
      final effectiveNow = now ?? DateTime.now();
      final result = TaskCompletionCommand(
        () => effectiveNow,
      ).complete(snapshot, scheduledAt: scheduledAt);

      final updatedMeta = Map<String, dynamic>.from(node.metadata);
      bool isCompleted = false;
      if (result.completed) {
        isCompleted = true;
        updatedMeta['lastCompletedAt'] = result.completedAt.toIso8601String();
        updatedMeta.remove('dueDate');
      } else {
        isCompleted = false;
        if (result.nextDue != null) {
          updatedMeta['dueDate'] = result.nextDue!.toIso8601String();
        }
        if (result.scheduledAt != null) {
          final completions = Map<String, dynamic>.from(
            updatedMeta['completions'] as Map? ?? {},
          );
          final schedStr = result.scheduledAt!.toUtc().toIso8601String();
          final compStr = result.completedAt.toUtc().toIso8601String();
          completions[schedStr] = compStr;
          updatedMeta['completions'] = completions;
        }
      }

      final updatedNode = TaskNode(
        id: node.id,
        text: node.text,
        isComplete: isCompleted,
        metadata: updatedMeta,
      );

      editor?.execute([
        ReplaceNodeRequest(existingNodeId: nodeId, newNode: updatedNode),
      ]);
      return result;
    }
    return null;
  }

  void reopenTaskInEditor(
    String nodeId, {
    DateTime? previousDue,
    DateTime? scheduledAt,
  }) {
    final node = document?.getNodeById(nodeId);
    if (node is TaskNode) {
      final updatedMeta = Map<String, dynamic>.from(node.metadata);
      if (previousDue != null) {
        updatedMeta['dueDate'] = previousDue.toIso8601String();
      }
      if (scheduledAt != null) {
        final completions = Map<String, dynamic>.from(
          updatedMeta['completions'] as Map? ?? {},
        );
        final schedStr = scheduledAt.toUtc().toIso8601String();
        completions.remove(schedStr);
        updatedMeta['completions'] = completions;
      }
      final updatedNode = TaskNode(
        id: node.id,
        text: node.text,
        isComplete: false,
        metadata: updatedMeta,
      );
      editor?.execute([
        ReplaceNodeRequest(existingNodeId: nodeId, newNode: updatedNode),
      ]);
    }
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
    final node = document?.getNodeById(nodeId);
    if (node is TaskNode) {
      final updatedMeta = Map<String, dynamic>.from(node.metadata);
      if (clearDueDate) {
        updatedMeta.remove('dueDate');
      } else if (dueDate != null) {
        updatedMeta['dueDate'] = dueDate.toIso8601String();
      }
      if (clearRecurrence) {
        updatedMeta.remove('recurrenceRule');
        updatedMeta.remove('recurrence');
      } else if (recurrence != null) {
        updatedMeta['recurrenceRule'] = recurrence;
        updatedMeta['recurrence'] = recurrence;
      }
      if (hasTime != null) {
        updatedMeta['hasTime'] = hasTime;
      }
      if (clearReminder) {
        updatedMeta.remove('reminder');
      } else if (reminder != null) {
        updatedMeta['reminder'] = reminder;
      }

      final updatedNode = TaskNode(
        id: node.id,
        text: node.text,
        isComplete: node.isComplete,
        metadata: updatedMeta,
      );
      editor?.execute([
        ReplaceNodeRequest(existingNodeId: nodeId, newNode: updatedNode),
      ]);
    }
  }

  void _setupEditor() {
    composer = MutableDocumentComposer();
    editor = createDefaultDocumentEditor(
      document: document!,
      composer: composer!,
    );
    editor!.reactionPipeline.removeWhere(
      (r) => r is HorizontalRuleConversionReaction,
    );
    editor!.reactionPipeline.add(
      const RandomDividerConversionReaction(dividerCount: _dividerCount),
    );
  }

  void bind(String noteId) {
    _noteId = noteId;
  }

  Future<void> pickAndAttachFile({bool imageOnly = false}) async {
    final result = await FilePicker.platform.pickFiles(
      type: imageOnly ? FileType.image : FileType.any,
    );
    if (result == null || result.files.isEmpty) return;

    final picked = result.files.single;
    final path = picked.path;
    if (path == null) return;

    final mimeType = lookupMimeType(path) ?? 'application/octet-stream';
    final uploader = _onUploadFile;
    if (uploader == null) return;

    attachFileFromPath(
      filePath: path,
      mimeType: mimeType,
      onUploadFile: (id, _, filePath, mimeType) =>
          uploader(id, filePath, mimeType),
      onError: () => AppMessenger.showError('Falha ao enviar anexo'),
    );
  }

  void attachFileFromPath({
    required String filePath,
    required String mimeType,
    required Future<void> Function(
      String id,
      String noteId,
      String filePath,
      String mimeType,
    )
    onUploadFile,
    required void Function() onError,
  }) {
    final noteId = _noteId;
    final editor = this.editor;
    if (noteId == null || editor == null) return;

    final id = Editor.createNodeId();
    editor.execute([
      InsertNodeAtCaretRequest(node: DocumentAttachmentNode(id: id)),
    ]);

    onUploadFile(id, noteId, filePath, mimeType).catchError((_) {
      if (editor.document.getNodeById(id) != null) {
        editor.execute([DeleteNodeRequest(nodeId: id)]);
      }
      onError();
    });
  }

  void suspendSync() {}

  void resumeSync() {}

  @override
  Future<void> dispose() async {
    onHasContentChanged = null;
    editor?.dispose();
    document?.dispose();
    composer?.dispose();
    focusNode.dispose();
    super.dispose();
  }
}
