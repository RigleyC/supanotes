
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mime/mime.dart';
import 'package:supanotes/features/notes/editor/document/attachment_nodes.dart';
import 'package:supanotes/features/notes/editor/document/empty_task_deletion_policy.dart';
import 'package:supanotes/features/notes/editor/document/hidden_task_editing_guard.dart';
import 'package:supanotes/features/notes/editor/document/note_document_constants.dart';
import 'package:supanotes/features/notes/editor/document/note_editor_commands.dart'
    show RandomDividerConversionReaction;
import 'package:supanotes/features/tasks/domain/task_completion_command.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';
import 'package:supanotes/features/tasks/domain/task_schedule_identity.dart';
import 'package:supanotes/shared/widgets/app_snackbar.dart';
import 'package:super_editor/super_editor.dart';


class NoteEditorController extends ChangeNotifier {
  NoteEditorController({
    required this.userId,
    required String noteId,
    List<DocumentNode>? nodes,
    Future<void> Function(String id, String filePath, String mimeType)?
    onUploadFile,
  }) : _onUploadFile = onUploadFile,
       _noteId = noteId,
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
  final Future<void> Function(String id, String filePath, String mimeType)?
  _onUploadFile;

  final MutableDocument document;
  late final Editor editor;
  late final MutableDocumentComposer composer;
  final FocusNode focusNode = FocusNode();
  void Function(bool)? onHasContentChanged;
  void Function()? _assertCanMutate;
  late final HiddenTaskEditingGuard _hiddenTaskEditingGuard;

  final String _noteId;

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
    if (node is TaskNode) {
      final dueDateStr = node.metadata['dueDate'] as String?;
      final hasTime = node.metadata['hasTime'] as bool? ?? false;
      final recurrenceStr = node.metadata['recurrenceRule'] as String?;
      final snapshot = TaskSnapshot(
        dueDate: _parseScheduleValue(dueDateStr, hasTime: hasTime),
        hasTime: hasTime,
        recurrence: TaskRecurrence.parse(recurrenceStr),
        completions: readScheduledCompletions(
          node.metadata['completions'],
          hasTime: hasTime,
        ),
      );
      final effectiveNow = now ?? DateTime.now();
      final result = TaskCompletionCommand(
        () => effectiveNow,
      ).complete(snapshot, scheduledAt: scheduledAt);

      final updatedMeta = Map<String, dynamic>.from(node.metadata);
      var isCompleted = false;
      if (result.completed) {
        isCompleted = true;
        updatedMeta['lastCompletedAt'] = result.completedAt
            .toUtc()
            .toIso8601String();
        updatedMeta.remove('dueDate');
      } else {
        isCompleted = false;
        if (result.scheduledAt != null) {
          final completions = Map<String, dynamic>.from(
            updatedMeta['completions'] as Map? ?? {},
          );
          final schedStr = scheduledAtKey(
            result.scheduledAt!,
            hasTime: hasTime,
          );
          final compStr = result.completedAt.toUtc().toIso8601String();
          completions.removeWhere((key, _) {
            final parsed = DateTime.tryParse(key);
            return parsed != null &&
                sameScheduledAt(parsed, result.scheduledAt!, hasTime: hasTime);
          });
          completions[schedStr] = compStr;
          updatedMeta['completions'] = completions;
        }
      }

      final updatedNode = node.copyTaskWith(
        isComplete: isCompleted,
        metadata: updatedMeta,
      );

      editor.execute([
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
    _assertCanMutate?.call();
    final node = document.getNodeById(nodeId);
    if (node is TaskNode) {
      final updatedMeta = Map<String, dynamic>.from(node.metadata);
      final hasTime = node.metadata['hasTime'] as bool? ?? false;
      if (scheduledAt == null && previousDue != null) {
        updatedMeta['dueDate'] = scheduledAtKey(previousDue, hasTime: hasTime);
      }
      if (scheduledAt != null) {
        final completions = Map<String, dynamic>.from(
          updatedMeta['completions'] as Map? ?? {},
        );
        completions.removeWhere((key, _) {
          final parsed = DateTime.tryParse(key);
          return parsed != null &&
              sameScheduledAt(parsed, scheduledAt, hasTime: hasTime);
        });
        updatedMeta['completions'] = completions;
      }
      final updatedNode = node.copyTaskWith(
        isComplete: false,
        metadata: updatedMeta,
      );
      editor.execute([
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
    _assertCanMutate?.call();
    final node = document.getNodeById(nodeId);
    if (node is TaskNode) {
      final updatedMeta = Map<String, dynamic>.from(node.metadata);
      final previousRecurrence = node.metadata['recurrenceRule'] as String?;
      final previousHasTime = node.metadata['hasTime'] as bool? ?? false;
      final previousDueDate = _parseScheduleValue(
        node.metadata['dueDate'] as String?,
        hasTime: previousHasTime,
      );
      final previousReminder = node.metadata['reminder'] as String?;
      final nextDueDate = clearDueDate ? null : dueDate ?? previousDueDate;
      final nextRecurrence = clearRecurrence
          ? null
          : recurrence ?? previousRecurrence;
      final nextHasTime = hasTime ?? previousHasTime;
      final nextReminder = clearReminder ? null : reminder ?? previousReminder;
      final dueDateChanged = previousDueDate == null
          ? nextDueDate != null
          : nextDueDate == null ||
                !sameScheduledAt(
                  previousDueDate,
                  nextDueDate,
                  hasTime: nextHasTime,
                );
      final scheduleChanged =
          dueDateChanged ||
          nextRecurrence != previousRecurrence ||
          nextHasTime != previousHasTime;
      if (nextReminder == previousReminder && !scheduleChanged) return;
      if (clearDueDate) {
        updatedMeta.remove('dueDate');
        updatedMeta.remove('hasTime');
      } else if (dueDate != null) {
        updatedMeta['dueDate'] = scheduledAtKey(dueDate, hasTime: nextHasTime);
      }
      if (clearRecurrence) {
        updatedMeta.remove('recurrenceRule');
      } else if (recurrence != null) {
        updatedMeta['recurrenceRule'] = recurrence;
      }
      if (hasTime != null) {
        updatedMeta['hasTime'] = hasTime;
      }
      if (clearReminder) {
        updatedMeta.remove('reminder');
      } else if (reminder != null) {
        updatedMeta['reminder'] = reminder;
      }
      if (scheduleChanged) updatedMeta.remove('completions');

      final updatedNode = node.copyTaskWith(metadata: updatedMeta);
      editor.execute([
        ReplaceNodeRequest(existingNodeId: nodeId, newNode: updatedNode),
      ]);
    }
  }

  DateTime? _parseScheduleValue(String? value, {required bool hasTime}) {
    return parseScheduledAt(value, hasTime: hasTime);
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

  Future<void> pickAndAttachFile({bool imageOnly = false}) async {
    _assertCanMutate?.call();
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
    _assertCanMutate?.call();
    final id = Editor.createNodeId();
    editor.execute([
      InsertNodeAtCaretRequest(node: DocumentAttachmentNode(id: id)),
    ]);

    onUploadFile(id, _noteId, filePath, mimeType).catchError((_) {
      try {
        _assertCanMutate?.call();
      } on StateError {
        return;
      }
      if (editor.document.getNodeById(id) != null) {
        editor.execute([DeleteNodeRequest(nodeId: id)]);
      }
      onError();
    });
  }

  @override
  Future<void> dispose() async {
    onHasContentChanged = null;
    document.removeListener(_clearSelectionIfHidden);
    editor.dispose();
    document.dispose();
    composer.dispose();
    focusNode.dispose();
    super.dispose();
  }
}
