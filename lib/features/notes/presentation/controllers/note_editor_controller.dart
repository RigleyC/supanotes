/// Shared controller for the note editor and inbox screens.
///
/// Owns the [MutableDocument], [Editor], [MutableDocumentComposer],
/// [FocusNode], [TextEditingController] (when a title is editable),
/// and a [SaveThrottle] instance that backs autosave and flush-on-pop.
/// Concrete screens decide what UI to build around the document; the
/// controller takes care of the lifecycle and the save path.
///
/// The controller holds the **document and save plumbing**; the host
/// screen provides the save callbacks and binds the [noteId] so the
/// controller never needs to cache a Riverpod [WidgetRef].
///
/// [flushBeforePop] evaluates the final document state: when both the
/// title and markdown content are empty (after trimming), the row is
/// deleted via [emptyNoteExit] instead of saved. If the host did not wire
/// an [emptyNoteExit] callback (e.g. inbox screen), the delete is a no-op
/// and the old content is preserved. This keeps "open and back out"
/// from leaving orphan blank notes behind without a separate flag.
library;

import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:super_editor/super_editor.dart';

import 'package:supanotes/core/utils/save_throttle.dart';
import 'package:supanotes/features/notes/data/markdown_serializer.dart';
import 'package:supanotes/features/notes/data/notes_repository.dart';
import 'package:supanotes/features/notes/domain/note_editor_commands.dart';
import 'package:supanotes/features/notes/domain/task_entry.dart';

const int _dividerCount = 35;

/// Signature for the snapshot save and empty-note exit operations.
///
/// The host screen provides these so the controller does not depend on
/// a particular [WidgetRef] or note id. Tests can supply a no-op or
/// recording implementation.
typedef SnapshotSave =
    Future<void> Function(
      String noteId,
      String title,
      String markdown,
      List<TaskEntry> tasks,
    );
typedef EmptyNoteExit = Future<void> Function(String noteId);

class NoteEditorController {
  NoteEditorController({
    required this.snapshotSave,
    this.emptyNoteExit,
  });

  /// Provided by the host. Keeps the controller free of [WidgetRef]
  /// references so it can be unit-tested in isolation.
  final SnapshotSave snapshotSave;
  final EmptyNoteExit? emptyNoteExit;

  MutableDocument? document;
  Editor? editor;
  MutableDocumentComposer? composer;
  FocusNode? focusNode;

  final _saveThrottle = SaveThrottle();

  /// The currently bound [noteId]. Non-null while the screen is mounted.
  String? _noteId;

  /// Initializes the editor from the given [content]. Wires the document listener.
  void init({required String content, String? title}) {
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
    focusNode = FocusNode();
    document!.addListener(_onDocumentChanged);
  }

  void bind(String noteId) {
    _noteId = noteId;
  }

  void _onDocumentChanged(DocumentChangeLog _) {
    final currentEditor = editor;
    final currentComposer = composer;
    if (currentEditor != null &&
        currentComposer != null &&
        NoteEditorCommands.convertDividerShortcut(
          currentEditor,
          currentComposer,
          dividerCount: _dividerCount,
        )) {
      return;
    }

    _scheduleSnapshotSave();
  }

  void _scheduleSnapshotSave() {
    final doc = document;
    if (doc == null) return;
    final generation = _saveThrottle.nextGeneration();
    _saveThrottle.schedule(
      generation: generation,
      operation: _runSnapshotSave,
    );
  }

  String _extractTitle(MutableDocument doc) {
    for (final node in doc) {
      if (node is TextNode) {
        final text = node.text.toPlainText().trim();
        if (text.isNotEmpty) {
          return text;
        }
      }
    }
    return '';
  }

  Future<void> _runSnapshotSave() async {
    final noteId = _noteId;
    final doc = document;
    if (noteId == null || doc == null) return;

    await snapshotSave(
      noteId,
      _extractTitle(doc),
      serializeNoteToMarkdown(doc),
      _extractTasks(doc),
    );
  }

  /// Forces a snapshot save immediately, bypassing the debounce.
  ///
  /// Unlike [flushBeforePop], this method does NOT call [emptyNoteExit].
  /// Use this before opening the task actions sheet so a newly typed
  /// checklist item exists in the tasks table.
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

  bool _isDocEmpty(MutableDocument doc) {
    for (final node in doc) {
      if (node is TextNode && node.text.toPlainText().trim().isNotEmpty) {
        return false;
      }
    }
    return true;
  }

  /// Captures the current final state and persists it immediately,
  /// bypassing the debounce. Call from [dispose] before cleaning up.
  ///
  /// When the markdown content is empty (after trimming), the row is
  /// deleted instead of saved. Screens that did not wire an [emptyNoteExit]
  /// callback (e.g. inbox) skip the delete, preserving the old content.
  void _flushAndSaveFinalState() {
    final noteId = _noteId;
    final doc = document;
    if (noteId == null || doc == null) return;

    final title = _extractTitle(doc);
    final markdown = serializeNoteToMarkdown(doc);
    final tasks = _extractTasks(doc);

    dev.log(
      '[NoteEditorController] _flushAndSaveFinalState: noteId=$noteId, '
      'markdownLength=${markdown.length}, titleLength=${title.length}',
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
        operation: () => snapshotSave(noteId, title, markdown, tasks),
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

/// Default save callbacks that write to the notes repository.
/// Screens that don't need to customize the save path can
/// pass these in directly.
Future<void> defaultSnapshotSave(
  INotesRepository repo,
  String noteId,
  String title,
  String markdown,
  List<TaskEntry> tasks,
) async {
  dev.log(
    '[defaultSnapshotSave] noteId=$noteId, markdownLength=${markdown.length}, tasks=${tasks.length}',
    name: 'NoteEditor',
  );
  await repo.saveNoteSnapshot(
        id: noteId,
        title: title,
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
