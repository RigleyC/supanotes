library;

import 'dart:async';
import 'dart:io';

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/core/auth/current_user.dart';
import 'package:supanotes/features/notes/data/attachments_repository.dart';
import 'package:supanotes/features/notes/data/notes_repository.dart';
import 'package:supanotes/features/notes/data/user_note_preferences_repository.dart';
import 'package:supanotes/features/notes/domain/note_model.dart';
import 'package:supanotes/features/notes/domain/note_strings.dart';
import 'package:supanotes/features/notes/presentation/controllers/note_editor_controller.dart';
import 'package:supanotes/features/notes/presentation/widgets/note_editor.dart';
import 'package:supanotes/features/notes/presentation/widgets/share_note_dialog.dart';
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
    final tasksAsync = ref.watch(tasksByNoteStreamProvider(widget.noteId));
    final tasksMap = tasksAsync.asData?.value != null
        ? {for (final t in tasksAsync.asData!.value) t.id: t}
        : const <String, TaskModel>{};

    return ref.watch(noteProvider(widget.noteId)).when(
      data: (note) {
        if (note == null) {
          return Scaffold(body: Center(child: Text(NoteStrings.errorNotFound)));
        }

        final isOwner = note.isOwner;
        final isReadOnly = note.isReadOnly;
        final hideCompleted = note.hideCompleted;

        return Scaffold(
          resizeToAvoidBottomInset: false,
          appBar: AppBar(
            title: isReadOnly ? Text('${NoteStrings.sharedByPrefix} ${note.sharedByEmail}') : null,
            actions: [
              AdaptivePopupMenuButton.icon<String>(
                icon: PlatformInfo.isIOS26OrHigher()
                    ? 'ellipsis'
                    : Icons.more_vert,
                onSelected: (index, entry) async {
                  switch (entry.value) {
                    case 'share':
                      await ShareNoteDialog.show(context, widget.noteId);
                    case 'hide_completed':
                      final userId = ref.read(currentUserIdProvider);
                      if (userId != null) {
                        await ref
                            .read(userNotePreferencesRepositoryProvider)
                            .setHideCompleted(
                              userId,
                              widget.noteId,
                              !hideCompleted,
                            );
                      }
                    case 'collapse_images':
                      await repo.updateNote(
                        widget.noteId,
                        collapseImages: !note.collapseImages,
                      );
                  }
                },
                items: [
                  if (isOwner)
                    AdaptivePopupMenuItem<String>(
                      label: NoteStrings.shareLabel,
                      icon: PlatformInfo.isIOS26OrHigher()
                          ? 'square.and.arrow.up'
                          : Icons.share_outlined,
                      value: 'share',
                    ),
                  AdaptivePopupMenuItem<String>(
                    label: hideCompleted
                        ? NoteStrings.showCompleted
                        : NoteStrings.hideCompleted,
                    icon: PlatformInfo.isIOS26OrHigher()
                        ? (hideCompleted ? 'eye' : 'eye.slash')
                        : (hideCompleted
                            ? Icons.visibility
                            : Icons.visibility_off),
                    value: 'hide_completed',
                  ),
                  if (isOwner)
                    AdaptivePopupMenuItem<String>(
                      label: note.collapseImages
                          ? 'Expandir imagens'
                          : 'Colapsar imagens',
                      icon: PlatformInfo.isIOS26OrHigher()
                          ? (note.collapseImages ? 'photo.fill' : 'photo')
                          : (note.collapseImages
                              ? Icons.image
                              : Icons.image_outlined),
                      value: 'collapse_images',
                    ),
                ],
              ),
              if (!isReadOnly)
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
              taskMetadata: tasksMap,
              hideCompleted: hideCompleted,
              collapseImages: note.collapseImages,
              isReadOnly: isReadOnly,
              snapshotSave: (noteId, markdown, tasks) =>
                  defaultSnapshotSave(repo, noteId, markdown, tasks),
              emptyNoteExit: (noteId) => defaultEmptyNoteExit(repo, noteId),
              onTaskLongPress: isReadOnly
                  ? null
                  : (taskId, flushSnapshot) =>
                      _openTaskActions(taskId, flushSnapshot),
              onTaskComplete: (taskId) =>
                  ref.read(tasksRepositoryProvider).completeTask(taskId),
              onTaskReopen: (taskId) =>
                  ref.read(tasksRepositoryProvider).reopenTask(taskId),
              onUploadFile: isReadOnly
                  ? null
                  : (noteId, filePath, mimeType) =>
                      ref.read(attachmentsRepositoryProvider).upload(
                        noteId: noteId, file: File(filePath), mimeType: mimeType,
                      ),
            ),
          ),
        );
      },
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => Scaffold(
        body: Center(child: Text('Error: $error')),
      ),
    );
  }
}
