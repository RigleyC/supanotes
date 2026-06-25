library;

import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

import 'package:supanotes/core/utils/save_throttle.dart';
import 'package:supanotes/features/notes/data/markdown_serializer.dart';
import 'package:supanotes/features/notes/data/notes_repository.dart';
import 'package:supanotes/features/notes/domain/attachment_nodes.dart';
import 'package:supanotes/features/notes/domain/keep_first_line_as_title_reaction.dart';
import 'package:supanotes/features/notes/domain/note_editor_commands.dart'
    show RandomDividerConversionReaction;
import 'package:supanotes/features/notes/domain/task_entry.dart';

const int _dividerCount = 35;

typedef SnapshotSave =
    Future<void> Function(
      String noteId,
      String markdown,
      List<TaskEntry> tasks,
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

  final _saveThrottle = SaveThrottle();

  String? _noteId;

  void init({required String content}) {
    dev.log(
      '[NoteEditorController.init] contentLength=${content.length}, content="$content"',
      name: 'NoteEditor',
    );
    document = parseNoteToMarkdown(content);
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

  void _onDocumentChanged(DocumentChangeLog _) => _scheduleSnapshotSave();

  void _scheduleSnapshotSave() {
    final doc = document;
    if (doc == null) return;
    final generation = _saveThrottle.nextGeneration();
    _saveThrottle.schedule(
      generation: generation,
      operation: _runSnapshotSave,
    );
  }

  Future<void> _runSnapshotSave() async {
    final noteId = _noteId;
    final doc = document;
    if (noteId == null || doc == null) return;

    await snapshotSave(
      noteId,
      serializeNoteToMarkdown(doc),
      _extractTasks(doc),
    );
  }

  Future<void> persistSnapshotNow() async {
    final noteId = _noteId;
    final doc = document;
    if (noteId == null || doc == null) return;

    final generation = _saveThrottle.nextGeneration();
    await _saveThrottle.flush(
      generation: generation,
      operation: _runSnapshotSave,
    );
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

    final markdown = serializeNoteToMarkdown(doc);
    final tasks = _extractTasks(doc);

    dev.log(
      '[NoteEditorController] _flushAndSaveFinalState: noteId=$noteId, '
      'markdownLength=${markdown.length}',
      name: 'NoteEditor',
    );

    if (_isDocEmpty(doc)) {
      dev.log(
        '[NoteEditorController] Deleting note (empty)',
        name: 'NoteEditor',
      );
      emptyNoteExit?.call(noteId);
    } else {
      final generation = _saveThrottle.nextGeneration();
      _saveThrottle.flush(
        generation: generation,
        operation: () => snapshotSave(noteId, markdown, tasks),
      );
    }
  }

  List<TaskEntry> _extractTasks(MutableDocument doc) {
    final tasks = <TaskEntry>[];
    for (final node in doc) {
      if (node is TaskNode) {
        tasks.add(
          TaskEntry(
            id: node.id,
            text: node.text.toPlainText(),
            isComplete: node.isComplete,
          ),
        );
      }
    }
    return tasks;
  }

  void dispose() {
    _flushAndSaveFinalState();
    _saveThrottle.dispose();
    document?.removeListener(_onDocumentChanged);
    document?.dispose();
    composer?.dispose();
    focusNode?.dispose();
  }
}

Future<void> defaultSnapshotSave(
  INotesRepository repo,
  String noteId,
  String markdown,
  List<TaskEntry> tasks,
) async {
  dev.log(
    '[defaultSnapshotSave] noteId=$noteId, markdownLength=${markdown.length}, tasks=${tasks.length}',
    name: 'NoteEditor',
  );
  await repo.saveNoteSnapshot(
        id: noteId,
        content: markdown,
        tasks: tasks,
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
