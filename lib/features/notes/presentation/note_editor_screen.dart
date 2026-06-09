library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:super_editor/super_editor.dart'
    hide serializeDocumentToMarkdown;

import 'package:supanotes/core/constants/app_constants.dart';
import 'package:supanotes/features/notes/data/markdown_serializer.dart';
import 'package:supanotes/features/notes/data/notes_repository.dart';
import 'package:supanotes/features/notes/domain/note_model.dart';
import 'package:supanotes/features/notes/domain/task_entry.dart';
import 'package:supanotes/features/notes/presentation/controllers/editor_status_notifier.dart';
import 'package:supanotes/features/notes/presentation/widgets/note_card.dart';
import 'package:supanotes/features/notes/presentation/widgets/note_toolbar.dart';
import 'package:supanotes/features/notes/presentation/widgets/save_indicator.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/theme/app_typography.dart';

final noteProvider = StreamProvider.family<NoteModel?, String>((ref, id) {
  return ref.watch(notesRepositoryProvider).watchNoteById(id);
});

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
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      ref.invalidate(noteProvider(widget.noteId));
    }
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

  void _onComposerChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _onDocumentChanged(DocumentChangeLog _) {
    final doc = _document;
    if (doc == null) return;
    final markdown = serializeDocumentToMarkdown(doc);
    final tasks = _extractTasks(doc);
    _saveDebounce?.cancel();
    ref.read(editorStatusProvider.notifier).saving();
    _saveDebounce = Timer(
      Duration(milliseconds: AppConstants.autoSaveDebounceMs),
      () => _flushContentSave(widget.noteId, markdown, tasks),
    );
  }

  List<TaskEntry> _extractTasks(MutableDocument doc) {
    final tasks = <TaskEntry>[];
    for (final node in doc) {
      if (node is TaskNode) {
        tasks.add(TaskEntry(
          id: node.id,
          text: node.text.toPlainText(),
          isComplete: node.isComplete,
        ));
      }
    }
    return tasks;
  }

  void _onTitleChanged(String value) {
    _titleDebounce?.cancel();
    ref.read(editorStatusProvider.notifier).saving();
    _titleDebounce = Timer(
      Duration(milliseconds: AppConstants.autoSaveDebounceMs),
      () => _flushTitleSave(widget.noteId, value),
    );
  }

  Future<void> _flushContentSave(
      String noteId, String markdown, List<TaskEntry> tasks) async {
    try {
      await ref
          .read(notesRepositoryProvider)
          .syncTasksFromDocument(noteId, tasks);
      await ref
          .read(notesRepositoryProvider)
          .updateNote(noteId, content: markdown);
      ref.read(editorStatusProvider.notifier).saved();
    } catch (_) {
      ref.read(editorStatusProvider.notifier).errored();
    }
  }

  Future<void> _flushTitleSave(String noteId, String title) async {
    try {
      await ref.read(notesRepositoryProvider).updateNote(
            noteId,
            title: title.isEmpty ? null : title,
          );
      ref.read(editorStatusProvider.notifier).saved();
    } catch (_) {
      ref.read(editorStatusProvider.notifier).errored();
    }
  }

  @override
  Widget build(BuildContext context) {
    final noteAsync = ref.watch(noteProvider(widget.noteId));
    final note = noteAsync.asData?.value;
    final editorStatus = ref.watch(editorStatusProvider);

    if (note != null && _document == null) {
      _document = parseMarkdownToDocument(note.content);
      _composer = MutableDocumentComposer();
      _editor = createDefaultDocumentEditor(
        document: _document!,
        composer: _composer!,
      );
      _editorFocusNode = FocusNode();
      _titleController = TextEditingController(text: note.title ?? '');
      _document!.addListener(_onDocumentChanged);
      _composer!.addListener(_onComposerChanged);
    }

    if (_document == null || _editor == null || _composer == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar.medium(
            title: Hero(
              tag: NoteCard.titleHeroTag(widget.noteId),
              child: TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  filled: false,
                  contentPadding: EdgeInsets.zero,
                  hintText: 'Sem título',
                ),
                style: AppTypography.textTheme.headlineMedium?.copyWith(
                  color: colorScheme.onSurface,
                ),
                onChanged: _onTitleChanged,
              ),
            ),
            actions: [
              SaveIndicator(state: editorStatus),
              IconButton(
                icon: Icon(
                  note?.favorite == true ? Icons.star : Icons.star_border,
                ),
                tooltip: note?.favorite == true ? 'Desfavoritar' : 'Favoritar',
                onPressed: () => ref
                    .read(notesRepositoryProvider)
                    .toggleFavorite(widget.noteId),
              ),
            ],
          ),
        ],
        body: Column(
          children: [
            Expanded(
              child: SuperEditor(
                editor: _editor!,
                focusNode: _editorFocusNode,
                stylesheet: defaultStylesheet.copyWith(
                  documentPadding: const EdgeInsets.all(AppSpacing.md),
                ),
              ),
            ),
            NoteToolbar(editor: _editor!, composer: _composer!),
          ],
        ),
      ),
    );
  }
}
