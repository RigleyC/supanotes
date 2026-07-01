library;

import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

import 'package:supanotes/features/notes/data/notes_repository.dart';
import 'package:supanotes/features/notes/domain/attachment_nodes.dart';
import 'package:supanotes/features/notes/domain/keep_first_line_as_title_reaction.dart';
import 'package:supanotes/features/notes/domain/note_editor_commands.dart'
    show RandomDividerConversionReaction;

const int _dividerCount = 35;

typedef SnapshotSave =
    Future<void> Function(
      String noteId,
      String content,
    );
typedef EmptyNoteExit = Future<void> Function(String noteId);

class NoteEditorController {
  NoteEditorController({
    required this.snapshotSave,
    this.emptyNoteExit,
  });

  final SnapshotSave snapshotSave;
  final EmptyNoteExit? emptyNoteExit;

  MutableDocument? document;
  Editor? editor;
  MutableDocumentComposer? composer;
  FocusNode? focusNode;

  String? _noteId;

  void init({required String content}) {
    dev.log(
      '[NoteEditorController.init] contentLength=${content.length}, content="$content"',
      name: 'NoteEditor',
    );
    document = _parseContentToDocument(content);
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
    focusNode = FocusNode();
    document!.addListener(_onDocumentChanged);
  }

  void bind(String noteId) {
    _noteId = noteId;
  }

  void _onDocumentChanged(DocumentChangeLog _) {
    _runSnapshotSave();
  }

  Future<void> _runSnapshotSave() async {
    final noteId = _noteId;
    final doc = document;
    if (noteId == null || doc == null) return;

    final content = doc
        .map((n) => n is TextNode ? n.text.toPlainText() : '')
        .where((t) => t.isNotEmpty)
        .join('\n');
    await snapshotSave(
      noteId,
      content,
    );
  }

  Future<void> persistSnapshotNow() async {
    await _runSnapshotSave();
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

    final content = doc
        .map((n) => n is TextNode ? n.text.toPlainText() : '')
        .where((t) => t.isNotEmpty)
        .join('\n');

    dev.log(
      '[NoteEditorController] _flushAndSaveFinalState: noteId=$noteId, '
      'contentLength=${content.length}',
      name: 'NoteEditor',
    );

    if (_isDocEmpty(doc)) {
      dev.log(
        '[NoteEditorController] Deleting note (empty)',
        name: 'NoteEditor',
      );
      emptyNoteExit?.call(noteId);
    } else {
      snapshotSave(noteId, content);
    }
  }

  void dispose() {
    _flushAndSaveFinalState();
    document?.removeListener(_onDocumentChanged);
    document?.dispose();
    composer?.dispose();
    focusNode?.dispose();
  }

  static MutableDocument _parseContentToDocument(String content) {
    final nodes = <DocumentNode>[];
    for (final line in content.split('\n')) {
      if (line.trimLeft().startsWith('- [ ] ') || line.trimLeft().startsWith('- [x] ')) {
        final isComplete = line.trimLeft().startsWith('- [x] ');
        final text = line.substring(line.indexOf('] ') + 2);
        nodes.add(
          TaskNode(
            id: Editor.createNodeId(),
            text: AttributedText(text.trimLeft()),
            isComplete: isComplete,
          ),
        );
      } else if (line.trim().isEmpty) {
        // skip blank lines between content blocks
      } else {
        nodes.add(
          TextNode(
            id: Editor.createNodeId(),
            text: AttributedText(line.trimLeft()),
          ),
        );
      }
    }
    return MutableDocument(nodes: nodes);
  }
}

Future<void> defaultSnapshotSave(
  INotesRepository repo,
  String noteId,
  String content,
) async {
  dev.log(
    '[defaultSnapshotSave] noteId=$noteId, contentLength=${content.length}',
    name: 'NoteEditor',
  );
  await repo.saveNoteSnapshot(
    id: noteId,
    content: content,
  );
  dev.log(
    '[defaultSnapshotSave] Completed noteId=$noteId',
    name: 'NoteEditor',
  );
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
