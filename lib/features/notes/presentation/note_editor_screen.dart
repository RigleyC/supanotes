library;

import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:super_editor/super_editor.dart';

import 'package:supanotes/features/notes/data/notes_repository.dart';
import 'package:supanotes/features/notes/domain/note_model.dart';
import 'package:supanotes/features/notes/presentation/controllers/note_editor_controller.dart';
import 'package:supanotes/features/notes/presentation/widgets/note_tags_chip_bar.dart';
import 'package:supanotes/features/notes/presentation/widgets/note_toolbar.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/theme/app_typography.dart';
import 'package:supanotes/features/notes/presentation/widgets/custom_task_component.dart';

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
  final _controller = NoteEditorController(
    contentSave: defaultContentSave,
    titleSave: defaultTitleSave,
    deleteNote: defaultDeleteNote,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _controller.bind(ref, widget.noteId);

    final asyncValue = ref.watch(noteProvider(widget.noteId));

    if (_controller.document == null) {
      dev.log(
        '[NoteEditor] noteId=${widget.noteId}, asyncValue=${asyncValue.runtimeType}, '
        'hasData=${asyncValue.hasValue}, isLoading=${asyncValue.isLoading}',
        name: 'NoteEditor',
      );
      if (asyncValue.isLoading) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      if (asyncValue.hasError) {
        return Scaffold(
          body: Center(child: Text('Error: ${asyncValue.error}')),
        );
      }
      final note = asyncValue.asData?.value;
      if (note == null) {
        return const Scaffold(
          body: Center(child: Text('Nota nao encontrada')),
        );
      }
      _controller.init(content: note.content, title: note.title);
    }

    if (_controller.document == null ||
        _controller.editor == null ||
        _controller.composer == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _controller.flushBeforePop();
        if (!context.mounted) return;
        context.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: TextField(
            controller: _controller.titleController,
            decoration: const InputDecoration(
              border: InputBorder.none,
              filled: false,
              contentPadding: EdgeInsets.zero,
              hintText: 'Sem titulo',
            ),
            style: AppTypography.textTheme.headlineMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
        body: Column(
          children: [
            NoteTagsChipBar(noteId: widget.noteId),
            Expanded(
              child: SuperEditor(
                editor: _controller.editor!,
                focusNode: _controller.focusNode,
                stylesheet: defaultStylesheet.copyWith(
                  documentPadding: const EdgeInsets.all(AppSpacing.md),
                ),
                componentBuilders: [
                  ...defaultComponentBuilders,
                  CustomTaskComponentBuilder(_controller.editor!),
                ],
              ),
            ),
            NoteToolbar(
              editor: _controller.editor!,
              composer: _controller.composer!,
            ),
          ],
        ),
      ),
    );
  }
}
