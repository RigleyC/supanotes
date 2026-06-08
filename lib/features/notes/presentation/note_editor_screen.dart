/// Note editor screen.
///
/// Owns a [SuperEditor] instance and delegates persistence (auto-save
/// with debounce, task sync, favorite toggle) to [NoteEditorController].
/// The markdown round-trip happens in `data/markdown_serializer.dart`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:super_editor/super_editor.dart'
    hide serializeDocumentToMarkdown;

import 'package:supanotes/features/notes/data/markdown_serializer.dart';
import 'package:supanotes/features/notes/presentation/controllers/note_editor_controller.dart';
import 'package:supanotes/features/notes/presentation/widgets/note_card.dart';
import 'package:supanotes/features/notes/presentation/widgets/note_toolbar.dart';
import 'package:supanotes/features/notes/presentation/widgets/save_indicator.dart';
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

  @override
  void initState() {
    super.initState();
    ref.read(noteEditorControllerProvider.notifier).loadNote(widget.noteId);
  }

  @override
  void dispose() {
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
    ref
        .read(noteEditorControllerProvider.notifier)
        .onContentChanged(widget.noteId, markdown, tasks);
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
    ref
        .read(noteEditorControllerProvider.notifier)
        .onTitleChanged(widget.noteId, value);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(noteEditorControllerProvider);
    final note = state.asData?.value.note;
    final saveState = state.asData?.value.saveState ?? SaveState.idle;

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
      body: CustomScrollView(slivers: [
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
              style: AppTypography.textTheme.titleLarge?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: AppTypography.semibold,
              ),
              onChanged: _onTitleChanged,
            ),
          ),
          actions: [
            SaveIndicator(state: saveState),
            IconButton(
              icon: Icon(
                note?.favorite == true ? Icons.star : Icons.star_border,
              ),
              tooltip: note?.favorite == true ? 'Desfavoritar' : 'Favoritar',
              onPressed: () => ref
                  .read(noteEditorControllerProvider.notifier)
                  .toggleFavorite(widget.noteId),
            ),
          ],
        ),
        Column(
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
      ]),
    );
  }
}
