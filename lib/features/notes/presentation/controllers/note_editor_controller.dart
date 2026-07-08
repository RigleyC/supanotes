library;

import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';
import 'package:yjs_dart/yjs_dart.dart';

import 'package:supanotes/features/notes/data/notes_repository.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/features/notes/domain/attachment_nodes.dart';
import 'package:supanotes/features/notes/domain/keep_first_line_as_title_reaction.dart';
import 'package:supanotes/features/notes/domain/note_sync_coordinator.dart';
import 'package:supanotes/features/notes/domain/yjs_doc_editor_bridge.dart';
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
  final FocusNode focusNode = FocusNode();

  NoteSyncCoordinator? _coordinator;
  YjsDocEditorBridge? _bridge;
  String? _noteId;
  Doc? _pendingBridgeDoc;

  void initFromNodes({required List<NoteNode> nodes, String? noteId}) {
    dev.log(
      '[NoteEditorController.initFromNodes] nodeCount=${nodes.length}',
      name: 'NoteEditor',
    );
    document = NoteSyncCoordinator.documentFromNodes(nodes);
    _noteId = noteId;
    _setupEditor();
    _setupCoordinator();
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

  void _setupCoordinator() {
    final db = _database;
    final noteId = _noteId;
    final doc = document;
    final ed = editor;
    if (db == null || noteId == null || doc == null || ed == null) return;
    _coordinator = NoteSyncCoordinator(
      database: db,
      noteId: noteId,
      userId: userId,
      document: doc,
      editor: ed,
    );

    if (_pendingBridgeDoc != null) {
      attachYjsBridge(doc: _pendingBridgeDoc!);
      _pendingBridgeDoc = null;
    }
  }

  void bind(String noteId) {
    _noteId = noteId;
  }

  void attachYjsBridge({
    required Doc doc,
  }) {
    final coordinator = _coordinator;
    if (coordinator == null) {
      _pendingBridgeDoc = doc;
      return;
    }
    _bridge = YjsDocEditorBridge(
      doc: doc,
      coordinator: coordinator,
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

  void syncTaskStates(Map<String, bool> taskCompletionMap) {
    _coordinator?.syncTaskStates(taskCompletionMap);
  }

  void updateNodesIncrementally(List<NoteNode> incomingNodes) {
    _coordinator?.updateNodesIncrementally(incomingNodes);
  }

  bool _isDocEmpty(MutableDocument doc) {
    if (doc.isEmpty) return true;
    if (doc.nodeCount == 1) {
      final firstNode = doc.first;
      if (firstNode is ParagraphNode && firstNode.text.toPlainText().trim().isEmpty) {
        return true;
      }
    }
    return false;
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
    _bridge?.dispose();
    _bridge = null;
    _coordinator?.dispose();
    editor?.dispose();
    document?.dispose();
    composer?.dispose();
    focusNode.dispose();
  }
}

Future<void> defaultEmptyNoteExit(INotesRepository repo, String noteId) async {
  dev.log('[defaultEmptyNoteExit] noteId=$noteId', name: 'NoteEditor');
  await repo.deleteIfEmptyOrTombstone(noteId);
  dev.log(
    '[defaultEmptyNoteExit] Completed noteId=$noteId',
    name: 'NoteEditor',
  );
}
