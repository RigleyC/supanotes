library;

import 'dart:developer' as dev;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mime/mime.dart';
import 'package:super_editor/super_editor.dart';
import 'package:yjs_dart/yjs_dart.dart';

import 'package:supanotes/features/notes/domain/attachment_nodes.dart';
import 'package:supanotes/features/tasks/domain/task_completion_command.dart';
import 'package:supanotes/features/notes/domain/editor_document_sync_manager.dart';
import 'package:supanotes/features/notes/domain/node_codec.dart';
import 'package:supanotes/features/notes/domain/yjs_doc_editor_bridge.dart';
import 'package:supanotes/features/notes/domain/yjs_node_codec.dart';
import 'package:supanotes/features/notes/domain/note_editor_commands.dart'
    show RandomDividerConversionReaction;
import 'package:supanotes/shared/widgets/app_snackbar.dart';

const int _dividerCount = 35;

class NoteEditorController extends ChangeNotifier {
  NoteEditorController({
    required this.userId,
    Future<void> Function(String id, String filePath, String mimeType)? onUploadFile,
  }) : _onUploadFile = onUploadFile;

  final String userId;
  final Future<void> Function(String id, String filePath, String mimeType)? _onUploadFile;

  MutableDocument? document;
  Editor? editor;
  MutableDocumentComposer? composer;
  final FocusNode focusNode = FocusNode();
  void Function(bool)? onHasContentChanged;

  EditorDocumentSyncManager? _coordinator;
  YjsDocEditorBridge? _bridge;
  String? _noteId;

  bool get hasDocument => document != null;

  void initFromDoc({
    required Doc doc,
    required String noteId,
    void Function({required bool isRemote})? onDocChanged,
    void Function(Set<String> nodeIds)? onDocCommitted,
  }) {
    dev.log(
      '[NoteEditorController.initFromDoc] noteId=$noteId',
      name: 'NoteEditor',
    );
    final nodes = noteNodesFromDoc(doc);
    document = NodeCodec.documentFromNodes(nodes);
    _noteId = noteId;
    _setupEditor();
    _coordinator = EditorDocumentSyncManager(
      document: document!,
      editor: editor!,
    );
    _bridge = YjsDocEditorBridge(
      doc: doc,
      userId: userId,
      coordinator: _coordinator!,
      onDocChanged: onDocChanged,
      onDocCommitted: onDocCommitted,
    );
    document!.addListener(_onDocChanged);
    dev.log(
      '[NoteEditorController.initFromDoc] done nodes=${nodes.length}',
      name: 'NoteEditor',
    );
    notifyListeners();
  }

  void _onDocChanged(DocumentChangeLog _) {
    onHasContentChanged?.call(document != null && document!.isNotEmpty);
  }

  TaskCompletionResult? completeTaskInYDoc(String nodeId,
      {DateTime? now, DateTime? scheduledAt}) {
    return _bridge?.completeTaskInYDoc(nodeId, now: now, scheduledAt: scheduledAt);
  }

  void reopenTaskInYDoc(String nodeId,
      {DateTime? previousDue, DateTime? scheduledAt}) {
    _bridge?.reopenTaskInYDoc(nodeId,
        previousDue: previousDue, scheduledAt: scheduledAt);
  }

  void updateTaskMetadataInYDoc(
    String nodeId, {
    DateTime? dueDate,
    String? recurrence,
    bool clearDueDate = false,
    bool clearRecurrence = false,
    bool? hasTime,
    String? reminder,
    bool clearReminder = false,
  }) {
    _bridge?.updateTaskMetadataInYDoc(
      nodeId,
      dueDate: dueDate,
      recurrence: recurrence,
      clearDueDate: clearDueDate,
      clearRecurrence: clearRecurrence,
      hasTime: hasTime,
      reminder: reminder,
      clearReminder: clearReminder,
    );
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
      onUploadFile: (id, _, filePath, mimeType) => uploader(id, filePath, mimeType),
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

  void suspendSync() {
    _coordinator?.suspendSync();
  }

  void resumeSync() {
    _coordinator?.resumeSync();
  }

  @override
  Future<void> dispose() async {
    document?.removeListener(_onDocChanged);
    onHasContentChanged = null;
    await _coordinator?.dispose();
    _bridge?.dispose();
    _bridge = null;
    editor?.dispose();
    document?.dispose();
    composer?.dispose();
    focusNode.dispose();
    super.dispose();
  }
}

