library;

import 'dart:async';

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/features/notes/data/notes_repository.dart';
import 'package:supanotes/features/notes/domain/note_model.dart';
import 'package:supanotes/features/notes/presentation/controllers/note_editor_controller.dart';
import 'package:supanotes/features/notes/presentation/widgets/note_editor.dart';
import 'package:supanotes/features/tasks/data/tasks_repository.dart';
import 'package:supanotes/features/tasks/domain/task_model.dart';
import 'package:supanotes/features/tasks/presentation/widgets/task_edit_sheet.dart';


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
  Future<void> _openTaskActions(
    String taskId,
    Future<void> Function() flushSnapshot,
  ) async {
    await flushSnapshot();
    if (!mounted) return;

    ref.invalidate(tasksByNoteStreamProvider(widget.noteId));
    final freshTasks = await ref.read(
      tasksByNoteStreamProvider(widget.noteId).future,
    );
    final freshMap = {for (final t in freshTasks) t.id: t};
    final task = freshMap[taskId];
    if (task == null || !mounted) return;

    await TaskEditSheet.show(
      context,
      noteId: task.noteId,
      task: task,
      allowTitleEdit: false,
      allowDelete: false,
      readOnlyTitle: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(notesRepositoryProvider);
    final asyncValue = ref.watch(noteProvider(widget.noteId));
    final tasksAsync = ref.watch(tasksByNoteStreamProvider(widget.noteId));
    final tasksMap = tasksAsync.asData?.value != null
        ? {for (final t in tasksAsync.asData!.value) t.id: t}
        : const <String, TaskModel>{};

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

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        actions: [
          AdaptivePopupMenuButton.icon<String>(
            icon: PlatformInfo.isIOS26OrHigher()
                ? 'ellipsis'
                : Icons.more_vert,
            onSelected: (index, entry) async {
              if (entry.value == 'hide_completed') {
                await repo.updateNote(
                  widget.noteId,
                  hideCompleted: !note.hideCompleted,
                );
              }
            },
            items: [
              AdaptivePopupMenuItem<String>(
                label: note.hideCompleted
                    ? 'Mostrar concluídas'
                    : 'Ocultar concluídas',
                icon: PlatformInfo.isIOS26OrHigher()
                    ? (note.hideCompleted ? 'eye' : 'eye.slash')
                    : (note.hideCompleted
                        ? Icons.visibility
                        : Icons.visibility_off),
                value: 'hide_completed',
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: () => FocusManager.instance.primaryFocus?.unfocus(),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: NoteEditor(
          noteId: widget.noteId,
          content: note.content,
          title: note.title,
          taskMetadata: tasksMap,
          hideCompleted: note.hideCompleted,
          snapshotSave: (noteId, title, markdown, tasks) =>
              defaultSnapshotSave(repo, noteId, title, markdown, tasks),
          emptyNoteExit: (noteId) => defaultEmptyNoteExit(repo, noteId),
          onTaskLongPress: (taskId, flushSnapshot) =>
              _openTaskActions(taskId, flushSnapshot),
          onTaskComplete: (taskId) =>
              ref.read(tasksRepositoryProvider).completeTask(taskId),
          onTaskReopen: (taskId) =>
              ref.read(tasksRepositoryProvider).reopenTask(taskId),
        ),
      ),
    );
  }
}
