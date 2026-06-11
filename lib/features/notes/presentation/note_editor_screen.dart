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
import 'package:supanotes/features/notes/presentation/widgets/custom_task_component.dart';
import 'package:supanotes/features/tasks/data/tasks_repository.dart';
import 'package:supanotes/features/tasks/domain/task_model.dart';
import 'package:supanotes/features/tasks/presentation/widgets/task_actions_sheet.dart';
import 'package:supanotes/shared/theme/app_typography.dart';

final noteProvider = StreamProvider.autoDispose.family<NoteModel?, String>((
  ref,
  id,
) {
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

  Map<String, TaskModel> _taskMapForNote(String noteId) {
    return ref
        .watch(tasksByNoteStreamProvider(noteId))
        .maybeWhen(
          data: (tasks) => {for (final task in tasks) task.id: task},
          orElse: () => const <String, TaskModel>{},
        );
  }

  NoteEditorController _controllerOrCreate() =>
      _controller ??= NoteEditorController(
        snapshotSave: (noteId, title, markdown, tasks) =>
            defaultSnapshotSave(ref, noteId, title, markdown, tasks),
        emptyNoteExit: (noteId) => defaultEmptyNoteExit(ref, noteId),
      );

  Future<void> _openTaskActions(
    NoteEditorController controller,
    String taskId,
  ) async {
    await controller.persistSnapshotNow();
    if (!mounted) return;

    ref.invalidate(tasksByNoteStreamProvider(widget.noteId));
    final freshTasks =
        await ref.read(tasksByNoteStreamProvider(widget.noteId).future);
    final freshMap = {for (final t in freshTasks) t.id: t};
    final task = freshMap[taskId];
    if (task == null) return;

    if (!mounted) return;
    await TaskActionsSheet.show(context, task: task);
  }

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

    final taskMetadataById = _taskMapForNote(widget.noteId);

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
            SliverFillRemaining(
              hasScrollBody: true,
              child: Column(
                children: [
                  Expanded(
                    child: SuperEditor(
                      editor: controller.editor!,
                      focusNode: controller.focusNode,
                      stylesheet: defaultStylesheet.copyWith(
                        documentPadding: EdgeInsets.zero,
                      ),
                      componentBuilders: [
                        ...defaultComponentBuilders,
                        CustomTaskComponentBuilder(
                          controller.editor!,
                          taskMetadataById: taskMetadataById,
                          onTaskLongPress: (taskId) =>
                              _openTaskActions(controller, taskId),
                        ),
                      ],
                    ),
                  ),
                  NoteToolbar(
                    editor: controller.editor!,
                    composer: controller.composer!,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
