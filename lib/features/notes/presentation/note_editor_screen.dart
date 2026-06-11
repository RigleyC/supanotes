library;

import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:super_editor/super_editor.dart';

import 'package:supanotes/features/notes/data/notes_repository.dart';
import 'package:supanotes/features/notes/domain/note_model.dart';
import 'package:supanotes/features/notes/presentation/controllers/note_editor_controller.dart';
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
  NoteEditorController? _controller;

  NoteEditorController _controllerOrCreate() =>
      _controller ??= NoteEditorController(
        snapshotSave: (noteId, title, markdown, tasks) =>
            defaultSnapshotSave(ref, noteId, title, markdown, tasks),
        emptyNoteExit: (noteId) => defaultEmptyNoteExit(ref, noteId),
      );

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controllerOrCreate();
    controller.bind(widget.noteId);

    final asyncValue = ref.watch(noteProvider(widget.noteId));
    

    if (controller.document == null) {
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
        return const Scaffold(body: Center(child: Text('Nota nao encontrada')));
      }
      controller.init(content: note.content, title: note.title);
    }

    if (controller.document == null ||
        controller.editor == null ||
        controller.composer == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await controller.flushBeforePop();
        if (!context.mounted) return;
        context.pop();
      },
      child: Scaffold(
        body: CustomScrollView(
          slivers: [
            SliverAppBar.medium(
              title: TextField(
                controller: controller.titleController,
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
            SuperEditor(
              editor: controller.editor!,
              focusNode: controller.focusNode,
              stylesheet: defaultStylesheet.copyWith(
                documentPadding:  EdgeInsets.zero,
              ),
              componentBuilders: [
                ...defaultComponentBuilders,
                CustomTaskComponentBuilder(controller.editor!),
              ],
            ),
            SliverToBoxAdapter(
              child: NoteToolbar(
                editor: controller.editor!,
                composer: controller.composer!,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
