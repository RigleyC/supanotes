library;

import 'dart:developer' as dev;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';
import 'package:dart_crdt/dart_crdt.dart';

import 'package:supanotes/features/notes/domain/note_node.dart';
import 'package:supanotes/features/notes/domain/attachment_nodes.dart';
import 'package:supanotes/features/notes/domain/keep_first_line_as_title_reaction.dart';
import 'package:supanotes/features/notes/domain/note_sync_coordinator.dart';
import 'package:supanotes/features/notes/domain/yjs_doc_editor_bridge.dart';
import 'package:supanotes/features/notes/domain/yjs_node_codec.dart';
import 'package:supanotes/features/notes/domain/node_sync_manager.dart';
import 'package:supanotes/features/notes/domain/note_editor_commands.dart'
    show RandomDividerConversionReaction;

const int _dividerCount = 35;

class NoteEditorController extends ChangeNotifier {
  NoteEditorController({
    required this.userId,
  });

  final String userId;

  MutableDocument? document;
  Editor? editor;
  MutableDocumentComposer? composer;
  final FocusNode focusNode = FocusNode();

  NoteSyncCoordinator? _coordinator;
  YjsDocEditorBridge? _bridge;
  String? _noteId;

  bool get hasDocument => document != null;

  void initFromDoc({
    required Doc doc,
    required String noteId,
    required void Function(Uint8List update) sendUpdate,
    void Function()? onDocChanged,
  }) {
    dev.log(
      '[NoteEditorController.initFromDoc] noteId=$noteId',
      name: 'NoteEditor',
    );
    final nodes = noteNodesFromDoc(doc);
    document = NodeSyncManager.documentFromNodes(nodes);
    _noteId = noteId;
    _setupEditor();
    _coordinator = NoteSyncCoordinator(
      document: document!,
      editor: editor!,
    );
    _bridge = YjsDocEditorBridge(
      doc: doc,
      coordinator: _coordinator!,
      sendUpdate: sendUpdate,
      onDocChanged: onDocChanged,
    );
    dev.log(
      '[NoteEditorController.initFromDoc] done nodes=${nodes.length}',
      name: 'NoteEditor',
    );
    notifyListeners();
  }

  void completeRecurringTask(String nodeId, DateTime nextDue) {
    _bridge?.completeRecurringTask(nodeId, nextDue);
  }

  void updateTaskMetadataInYDoc(
    String nodeId, {
    DateTime? dueDate,
    String? recurrence,
    bool clearDueDate = false,
    bool clearRecurrence = false,
  }) {
    _bridge?.updateTaskMetadataInYDoc(
      nodeId,
      dueDate: dueDate,
      recurrence: recurrence,
      clearDueDate: clearDueDate,
      clearRecurrence: clearRecurrence,
    );
  }

  void syncTaskStates(Map<String, bool> taskCompletionMap) {
    _coordinator?.syncTaskStates(taskCompletionMap);
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
    editor!.reactionPipeline.add(const KeepFirstLineAsTitleReaction());
  }

  void bind(String noteId) {
    _noteId = noteId;
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

  void updateNodesIncrementally(List<NoteNode> incomingNodes) {
    _coordinator?.updateNodesIncrementally(incomingNodes);
  }

  @override
  Future<void> dispose() async {
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

