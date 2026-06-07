/// Note editor screen.
///
/// Owns a [SuperEditor] instance, a debounced auto-save loop and a
/// task-sync loop that keeps the in-document `TaskNode`s in lock-step
/// with the local Drift `tasks` table. The `MarkdownSerializer`
/// (defined in `../data/markdown_serializer.dart`) is the only
/// markdown<->document bridge.
library;

import 'dart:async';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:super_editor/super_editor.dart'
    hide serializeDocumentToMarkdown;

import 'package:supanotes/core/constants/app_constants.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/features/notes/data/local/notes_local_repository.dart';
import 'package:supanotes/features/notes/data/markdown_serializer.dart';
import 'package:supanotes/features/notes/presentation/widgets/note_card.dart';
import 'package:supanotes/features/notes/presentation/widgets/note_toolbar.dart';
import 'package:supanotes/features/notes/presentation/widgets/save_indicator.dart';
import 'package:supanotes/features/tasks/data/local/tasks_local_repository.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/theme/app_typography.dart';

class NoteEditorScreen extends ConsumerStatefulWidget {
  final String noteId;

  const NoteEditorScreen({super.key, required this.noteId});

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  MutableDocument? _document;
  Editor? _editor;
  MutableDocumentComposer? _composer;
  FocusNode? _editorFocusNode;
  TextEditingController? _titleController;

  Timer? _saveDebounce;
  Timer? _titleDebounce;
  bool _favorite = false;
  SaveState _saveState = SaveState.idle;

  @override
  void initState() {
    super.initState();
    _loadNote();
  }

  Future<void> _loadNote() async {
    final note = await ref
        .read(notesLocalRepositoryProvider)
        .getNoteById(widget.noteId);
    if (note == null || !mounted) return;

    _document = parseMarkdownToDocument(note.content);
    _composer = MutableDocumentComposer();
    _editor = createDefaultDocumentEditor(
      document: _document!,
      composer: _composer!,
    );
    _editorFocusNode = FocusNode();
    _titleController = TextEditingController(text: note.title ?? '');
    _favorite = note.favorite;

    _document!.addListener(_onDocumentChanged);
    _composer!.addListener(_onComposerChanged);

    setState(() {});
  }

  void _onComposerChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _onDocumentChanged(DocumentChangeLog _) {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(
      Duration(milliseconds: AppConstants.autoSaveDebounceMs),
      _flushSave,
    );
  }

  void _onTitleChanged(String value) {
    _titleDebounce?.cancel();
    _titleDebounce = Timer(
      Duration(milliseconds: AppConstants.autoSaveDebounceMs),
      () => _saveTitle(value),
    );
  }

  Future<void> _saveTitle(String title) async {
    final companion = NotesCompanion(
      id: drift.Value(widget.noteId),
      title: drift.Value(title.isEmpty ? null : title),
      favorite: drift.Value(_favorite),
      updatedAt: drift.Value(DateTime.now().toUtc()),
      isDirty: const drift.Value(true),
    );
    try {
      await ref
          .read(notesLocalRepositoryProvider)
          .updateNoteRaw(companion);
      _setSaveState(SaveState.saved);
    } catch (_) {
      _setSaveState(SaveState.error);
    }
  }

  Future<void> _toggleFavorite() async {
    setState(() => _favorite = !_favorite);
    final id = widget.noteId;
    final companion = NotesCompanion(
      id: drift.Value(id),
      favorite: drift.Value(_favorite),
      updatedAt: drift.Value(DateTime.now().toUtc()),
      isDirty: const drift.Value(true),
    );
    try {
      await ref
          .read(notesLocalRepositoryProvider)
          .updateNoteRaw(companion);
    } catch (_) {
      if (mounted) {
        setState(() => _favorite = !_favorite);
      }
    }
  }

  Future<void> _flushSave() async {
    if (_document == null) return;
    _setSaveState(SaveState.saving);
    final markdown = serializeDocumentToMarkdown(_document!);
    try {
      await _syncTasks(_document!, markdown);
      await ref
          .read(notesLocalRepositoryProvider)
          .updateNoteContent(widget.noteId, markdown);
      _setSaveState(SaveState.saved);
    } catch (_) {
      _setSaveState(SaveState.error);
    }
  }

  Future<void> _syncTasks(MutableDocument doc, String markdown) async {
    final tasksRepo = ref.read(tasksLocalRepositoryProvider);
    final currentTasks = await tasksRepo.watchNoteTasks(widget.noteId).first;
    final currentIds = currentTasks.map((t) => t.id).toSet();
    final docIds = <String>{};
    for (final node in doc) {
      if (node is TaskNode) {
        final text = node.text.toPlainText();
        docIds.add(node.id);
        if (currentIds.contains(node.id)) {
          await tasksRepo.updateTask(TasksCompanion(
            id: drift.Value(node.id),
            title: drift.Value(text),
            status:
                drift.Value(node.isComplete ? 'completed' : 'pending'),
          ));
        } else {
          await tasksRepo.createTask(
            id: node.id,
            noteId: widget.noteId,
            title: text,
            position: 0,
            status: node.isComplete ? 'completed' : 'pending',
          );
        }
      }
    }
    final removed = currentIds.difference(docIds);
    for (final id in removed) {
      await tasksRepo.deleteTask(id);
    }
    assert(markdown.isNotEmpty || docIds.isEmpty);
  }

  void _setSaveState(SaveState state) {
    if (!mounted) return;
    setState(() => _saveState = state);
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _titleDebounce?.cancel();
    _titleController?.dispose();
    _composer?.removeListener(_onComposerChanged);
    _document?.removeListener(_onDocumentChanged);
    _document?.dispose();
    _composer?.dispose();
    _editorFocusNode?.dispose();
    super.dispose();
  }

  Future<void> _saveAndPop() async {
    _saveDebounce?.cancel();
    _titleDebounce?.cancel();
    if (_document != null) {
      await _flushSave();
      final title = _titleController?.text ?? '';
      if (title.isNotEmpty) {
        await _saveTitle(title);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_document == null || _editor == null || _composer == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final colorScheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _saveAndPop().then((_) {
          if (context.mounted) {
            context.pop();
          }
        });
      },
      child: Scaffold(
        appBar: AppBar(
          title: Hero(
            tag: NoteCard.titleHeroTag(widget.noteId),
            child: Material(
              type: MaterialType.transparency,
              child: TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  filled: false,
                  contentPadding: EdgeInsets.zero,
                  hintText: 'Sem título',
                ),
                style: AppTypography.textTheme.titleLarge?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: AppTypography.semibold,
                ),
                onChanged: _onTitleChanged,
              ),
            ),
          ),
        actions: [
          SaveIndicator(state: _saveState),
          IconButton(
            icon: Icon(_favorite ? Icons.star : Icons.star_border),
            tooltip: _favorite ? 'Desfavoritar' : 'Favoritar',
            onPressed: _toggleFavorite,
          ),
        ],
      ),
      body: Column(
        children: [
          NoteToolbar(editor: _editor!, composer: _composer!),
          Expanded(
            child: SuperEditor(
              editor: _editor!,
              focusNode: _editorFocusNode,
              stylesheet: defaultStylesheet.copyWith(
                documentPadding: const EdgeInsets.all(AppSpacing.md),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
}
