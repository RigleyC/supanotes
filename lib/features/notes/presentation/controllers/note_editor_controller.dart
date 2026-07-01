library;

import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

import 'package:supanotes/features/notes/data/notes_repository.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/features/notes/domain/attachment_nodes.dart';
import 'package:supanotes/features/notes/domain/keep_first_line_as_title_reaction.dart';
import 'package:supanotes/features/notes/domain/node_sync_manager.dart';
import 'package:supanotes/features/notes/domain/note_editor_commands.dart'
    show RandomDividerConversionReaction;

const int _dividerCount = 35;

typedef EmptyNoteExit = Future<void> Function(String noteId);

class NoteEditorController {
  NoteEditorController({
    required this.userId,
    this.emptyNoteExit,
    AppDatabase? database,
  }) : _database = database;

  final String userId;
  final EmptyNoteExit? emptyNoteExit;
  final AppDatabase? _database;

  MutableDocument? document;
  Editor? editor;
  MutableDocumentComposer? composer;
  FocusNode? focusNode;

  NodeSyncManager? _nodeSyncManager;
  String? _noteId;

  void initFromNodes({
    required List<NoteNode> nodes,
    String? noteId,
  }) {
    dev.log(
      '[NoteEditorController.initFromNodes] nodeCount=${nodes.length}',
      name: 'NoteEditor',
    );
    document = NodeSyncManager.documentFromNodes(nodes);
    _noteId = noteId;
    _setupEditor();
    _setupNodeSyncManager();
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
    editor!.reactionPipeline.add(
      const KeepFirstLineAsTitleReaction(),
    );
    // Reuse existing focus node if controller is re-initialized
    focusNode ??= FocusNode();
  }

  void _setupNodeSyncManager() {
    final db = _database;
    final noteId = _noteId;
    final doc = document;
    if (db == null || noteId == null || doc == null) return;
    _nodeSyncManager = NodeSyncManager(
      database: db,
      noteId: noteId,
      userId: userId,
      document: doc,
    );
  }

  void bind(String noteId) {
    _noteId = noteId;
  }

  void attachFileFromPath({
    required String filePath,
    required String mimeType,
    required Future<void> Function(String id, String noteId, String filePath, String mimeType) onUploadFile,
    required void Function() onError,
  }) {
    final noteId = _noteId;
    final editor = this.editor;
    if (noteId == null || editor == null) return;

    final id = Editor.createNodeId();
    editor.execute([InsertNodeAtCaretRequest(node: DocumentAttachmentNode(id: id))]);

    onUploadFile(id, noteId, filePath, mimeType).catchError((_) {
      if (editor.document.getNodeById(id) != null) {
        editor.execute([DeleteNodeRequest(nodeId: id)]);
      }
      onError();
    });
  }

  void updateNodesIncrementally(List<NoteNode> incomingNodes) {
    final doc = document;
    final ed = editor;
    if (doc == null || ed == null) return;

    final requests = <EditRequest>[];
    final incomingIds = incomingNodes.map((n) => n.id).toSet();

    for (final node in doc) {
      if (!incomingIds.contains(node.id)) {
        requests.add(DeleteNodeRequest(nodeId: node.id));
      }
    }

    for (int i = 0; i < incomingNodes.length; i++) {
      final incoming = incomingNodes[i];
      final existingNode = doc.getNodeById(incoming.id);

      if (existingNode == null) {
        final newNode = NodeSyncManager.createNodeFromSchema(incoming);
        requests.add(InsertNodeAtIndexRequest(nodeIndex: i, newNode: newNode));
      } else {
        final newNode = NodeSyncManager.createNodeFromSchema(incoming);
        if (_isNodeModified(existingNode, newNode)) {
          requests.add(
            ReplaceNodeRequest(
              existingNodeId: incoming.id,
              newNode: newNode,
            ),
          );
        }
      }
    }

    if (requests.isNotEmpty) {
      ed.execute(requests);
    }
  }

  bool _isNodeModified(DocumentNode existing, DocumentNode incoming) {
    if (existing.runtimeType != incoming.runtimeType) return true;

    if (existing is TextNode && incoming is TextNode) {
      if (existing.text != incoming.text) return true;
    }

    if (existing is ParagraphNode && incoming is ParagraphNode) {
      if (existing.metadata['blockType'] != incoming.metadata['blockType']) return true;
    }

    if (existing is TaskNode && incoming is TaskNode) {
      if (existing.isComplete != incoming.isComplete) return true;
      if (existing.indent != incoming.indent) return true;
    }

    if (existing is ListItemNode && incoming is ListItemNode) {
      if (existing.indent != incoming.indent) return true;
      if (existing.type != incoming.type) return true;
    }

    return false;
  }

  bool _isDocEmpty(MutableDocument doc) {
    for (final node in doc) {
      if (node is TextNode && node.text.toPlainText().trim().isNotEmpty) {
        return false;
      }
    }
    return true;
  }

  void _flushAndSaveFinalState() {
    final noteId = _noteId;
    final doc = document;
    if (noteId == null || doc == null) return;

    if (_isDocEmpty(doc)) {
      dev.log(
        '[NoteEditorController] Deleting note (empty)',
        name: 'NoteEditor',
      );
      emptyNoteExit?.call(noteId);
    }
  }

  void dispose() {
    _flushAndSaveFinalState();
    _nodeSyncManager?.dispose();
    document?.dispose();
    composer?.dispose();
    focusNode?.dispose();
  }
}

Future<void> defaultEmptyNoteExit(INotesRepository repo, String noteId) async {
  dev.log(
    '[defaultEmptyNoteExit] noteId=$noteId',
    name: 'NoteEditor',
  );
  await repo.deleteIfEmptyOrTombstone(noteId);
  dev.log(
    '[defaultEmptyNoteExit] Completed noteId=$noteId',
    name: 'NoteEditor',
  );
}
