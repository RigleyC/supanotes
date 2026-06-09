/// Shared controller for the note editor and inbox screens.
///
/// Owns the [MutableDocument], [Editor], [MutableDocumentComposer],
/// [FocusNode], [TextEditingController] (when a title is editable),
/// and the [SaveThrottle] instances that back autosave and flush-on-pop.
/// Concrete screens decide what UI to build around the document; the
/// controller takes care of the lifecycle and the save path.
///
/// The controller holds the **document and save plumbing**; the host
/// screen provides the [WidgetRef] and target [noteId] at every save
/// call so the controller never needs to cache either.
///
/// [flushBeforePop] evaluates the final document state: when both the
/// title and markdown content are empty (after trimming), the row is
/// deleted via [deleteNote] instead of saved. If the host did not wire
/// a [deleteNote] callback (e.g. inbox screen), the delete is a no-op
/// and the old content is preserved. This keeps "open and back out"
/// from leaving orphan blank notes behind without a separate flag.
library;

import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:super_editor/super_editor.dart';

import 'package:supanotes/core/utils/save_throttle.dart';
import 'package:supanotes/features/notes/data/markdown_serializer.dart'
    hide serializeDocumentToMarkdown;
import 'package:supanotes/features/notes/data/notes_repository.dart';
import 'package:supanotes/features/notes/domain/task_entry.dart';

/// Signature for the content, title and delete operations.
///
/// The host screen provides these so the controller does not depend on
/// a particular [WidgetRef] or note id. Tests can supply a no-op or
/// recording implementation.
typedef ContentSave =
    Future<void> Function(
      WidgetRef ref,
      String noteId,
      String markdown,
      List<TaskEntry> tasks,
    );
typedef TitleSave =
    Future<void> Function(WidgetRef ref, String noteId, String title);
typedef DeleteNote = Future<void> Function(WidgetRef ref, String noteId);

class NoteEditorController {
  NoteEditorController({
    this.editableTitle = true,
    required this.contentSave,
    required this.titleSave,
    this.deleteNote,
  });

  /// Whether the host screen lets the user edit a title. Inbox notes
  /// pass `false` because they have no title.
  final bool editableTitle;

  /// Provided by the host. Keeps the controller free of [WidgetRef]
  /// references so it can be unit-tested in isolation.
  final ContentSave contentSave;
  final TitleSave titleSave;
  final DeleteNote? deleteNote;

  MutableDocument? document;
  Editor? editor;
  MutableDocumentComposer? composer;
  FocusNode? focusNode;
  TextEditingController? titleController;

  final _contentThrottle = SaveThrottle();
  final _titleThrottle = SaveThrottle();

  /// The currently bound [WidgetRef] and [noteId]. Both are non-null
  /// while the screen is mounted.
  WidgetRef? _ref;
  String? _noteId;

  /// Initializes the editor from the given [content] and optional
  /// [title]. Wires the document listener and, if [editableTitle],
  /// the title controller listener.
  void init({required String content, String? title}) {
    dev.log(
      '[NoteEditorController.init] contentLength=${content.length}, content="$content"',
      name: 'NoteEditor',
    );
    document = parseMarkdownToDocument(content);
    composer = MutableDocumentComposer();
    editor = createDefaultDocumentEditor(
      document: document!,
      composer: composer!,
    );
    focusNode = FocusNode();
    if (editableTitle) {
      titleController = TextEditingController(text: title ?? '');
      titleController!.addListener(_onTitleChanged);
    }
    document!.addListener(_onDocumentChanged);
  }

  void bind(WidgetRef ref, String noteId) {
    _ref = ref;
    _noteId = noteId;
  }

  void _onDocumentChanged(DocumentChangeLog _) {
    final doc = document;
    if (doc == null) return;
    final markdown = serializeDocumentToMarkdown(doc);
    final tasks = _extractTasks(doc);
    _contentThrottle.schedule(
      generation: _contentThrottle.nextGeneration(),
      operation: () => _runContentSave(markdown, tasks),
    );
  }

  void _onTitleChanged() {
    final value = titleController?.text;
    if (value == null) return;
    _titleThrottle.schedule(
      generation: _titleThrottle.nextGeneration(),
      operation: () => _runTitleSave(value),
    );
  }

  /// Captures the current final state and persists it immediately,
  /// bypassing the debounce. Call from the [PopScope] handler before
  /// navigating away.
  ///
  /// When both the title and markdown content are empty (after
  /// trimming), the row is deleted instead of saved. Screens that did
  /// not wire a [deleteNote] callback (e.g. inbox) skip the delete,
  /// preserving the old content.
  Future<void> flushBeforePop() async {
    final doc = document;
    final title = titleController?.text ?? '';
    final markdown = doc != null ? serializeDocumentToMarkdown(doc) : '';

    dev.log(
      '[NoteEditorController] flushBeforePop: noteId=$_noteId, '
      'markdownLength=${markdown.length}, titleLength=${title.length}',
      name: 'NoteEditor',
    );

    if (deleteNote != null && markdown.trim().isEmpty && title.trim().isEmpty) {
      dev.log(
        '[NoteEditorController] Deleting note (empty)',
        name: 'NoteEditor',
      );
      await _runDelete();
      return;
    }

    final contentGen = _contentThrottle.nextGeneration();
    final titleGen = _titleThrottle.nextGeneration();
    if (doc != null) {
      final tasks = _extractTasks(doc);
      dev.log(
        '[NoteEditorController] Saving content: noteId=$_noteId, tasks=${tasks.length}',
        name: 'NoteEditor',
      );
      await _contentThrottle.flush(
        generation: contentGen,
        operation: () => _runContentSave(markdown, tasks),
      );
    }
    if (title.isNotEmpty || editableTitle) {
      dev.log(
        '[NoteEditorController] Saving title: noteId=$_noteId, title=$title',
        name: 'NoteEditor',
      );
      await _titleThrottle.flush(
        generation: titleGen,
        operation: () => _runTitleSave(title),
      );
    }
  }

  Future<void> _runContentSave(String markdown, List<TaskEntry> tasks) async {
    final ref = _ref;
    final noteId = _noteId;
    if (ref == null || noteId == null) return;
    await contentSave(ref, noteId, markdown, tasks);
  }

  Future<void> _runTitleSave(String title) async {
    final ref = _ref;
    final noteId = _noteId;
    if (ref == null || noteId == null) return;
    await titleSave(ref, noteId, title);
  }

  Future<void> _runDelete() async {
    final ref = _ref;
    final noteId = _noteId;
    final delete = deleteNote;
    if (ref == null || noteId == null || delete == null) return;
    await delete(ref, noteId);
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
    _contentThrottle.dispose();
    _titleThrottle.dispose();
    if (editableTitle) {
      titleController?.removeListener(_onTitleChanged);
      titleController?.dispose();
    }
    document?.removeListener(_onDocumentChanged);
    document?.dispose();
    composer?.dispose();
    focusNode?.dispose();
  }
}

/// Default save callbacks that write to the notes repository via
/// Riverpod. Screens that don't need to customize the save path can
/// pass these in directly.
Future<void> defaultContentSave(
  WidgetRef ref,
  String noteId,
  String markdown,
  List<TaskEntry> tasks,
) async {
  dev.log(
    '[defaultContentSave] noteId=$noteId, markdownLength=${markdown.length}, tasks=${tasks.length}, markdown="$markdown"',
    name: 'NoteEditor',
  );
  final repo = ref.read(notesRepositoryProvider);
  await repo.syncTasksFromDocument(noteId, tasks);
  final note = await repo.watchNoteById(noteId).first;
  dev.log(
    '[defaultContentSave] noteId=$noteId, noteExists=${note != null}, currentContentLength=${note?.content.length}',
    name: 'NoteEditor',
  );
  if (note == null) {
    await repo.upsertNote(id: noteId, content: markdown);
  } else {
    await repo.updateNote(noteId, content: markdown);
  }
  dev.log('[defaultContentSave] Completed noteId=$noteId', name: 'NoteEditor');
}

Future<void> defaultTitleSave(
  WidgetRef ref,
  String noteId,
  String title,
) async {
  dev.log(
    '[defaultTitleSave] noteId=$noteId, title=$title',
    name: 'NoteEditor',
  );
  final repo = ref.read(notesRepositoryProvider);
  final note = await repo.watchNoteById(noteId).first;
  if (note == null) {
    await repo.upsertNote(
      id: noteId,
      title: title.isEmpty ? null : title,
      content: '',
    );
  } else {
    await repo.updateNote(noteId, title: title.isEmpty ? null : title);
  }
  dev.log('[defaultTitleSave] Completed noteId=$noteId', name: 'NoteEditor');
}

Future<void> defaultDeleteNote(WidgetRef ref, String noteId) async {
  dev.log('[defaultDeleteNote] noteId=$noteId', name: 'NoteEditor');
  await ref.read(notesRepositoryProvider).softDelete(noteId);
  dev.log('[defaultDeleteNote] Completed noteId=$noteId', name: 'NoteEditor');
}
