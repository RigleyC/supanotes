library;

import 'dart:async';
import 'dart:io';

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supanotes/features/tasks/presentation/widgets/task_metadata_sheet.dart';

import 'package:supanotes/shared/widgets/adaptive_sliver_nav_bar.dart';
import 'package:supanotes/shared/widgets/app_bottom_sheet.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/features/tasks/presentation/controllers/task_snackbar_helper.dart';

import 'package:supanotes/core/auth/current_user.dart';
import 'package:supanotes/features/notes/data/attachments_repository.dart';
import 'package:supanotes/features/notes/data/notes_repository.dart';
import 'package:supanotes/features/notes/data/user_note_preferences_repository.dart';
import 'package:supanotes/features/notes/domain/note_strings.dart';
import 'package:supanotes/features/notes/presentation/controllers/note_editor_controller.dart';
import 'package:supanotes/features/notes/presentation/controllers/notes_providers.dart';
import 'package:supanotes/features/notes/presentation/controllers/note_editor_delegate.dart';
import 'package:supanotes/features/notes/presentation/widgets/note_editor.dart';
import 'package:supanotes/features/notes/presentation/widgets/share_note_sheet.dart';
import 'package:supanotes/features/tasks/data/tasks_repository.dart';
import 'package:supanotes/features/tasks/domain/task_model.dart';

class NoteEditorScreen extends ConsumerStatefulWidget {
  final String noteId;

  const NoteEditorScreen({super.key, required this.noteId});

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  Future<void> _openTaskActions(
    TaskModel? task,
    Future<void> Function() flushSnapshot,
  ) async {
    await flushSnapshot();
    if (!mounted || task == null) return;

    await TaskMetadataSheet.show(
      context,
      noteId: task.noteId,
      task: task,
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(notesRepositoryProvider);
    final nodesAsync = ref.watch(noteNodesProvider(widget.noteId));
    final noteWithTasksAsync = ref.watch(noteWithTasksProvider(widget.noteId));

    return nodesAsync.when(
      data: (nodes) {
        return noteWithTasksAsync.when(
          data: (noteWithTasks) {
            final note = noteWithTasks.note;
            if (note == null) {
              return Scaffold(body: Center(child: Text(NoteStrings.errorNotFound)));
            }

            final tasksMap = noteWithTasks.taskById;

            final isOwner = note.isOwner;
            final isReadOnly = note.isReadOnly;
            final hideCompleted = note.hideCompleted;

            return Scaffold(
              resizeToAvoidBottomInset: false,
              body: NoteEditor(
                noteId: widget.noteId,
                nodes: nodes,
                taskMetadata: tasksMap,
                hideCompleted: hideCompleted,
                collapseImages: note.collapseImages,
                isReadOnly: isReadOnly,
                appBar: AdaptiveSliverNavBar(
                  title: isReadOnly ? Text('${NoteStrings.sharedByPrefix} ${note.sharedByEmail}') : null,
                  actions: [
                    AdaptivePopupMenuButton.icon<String>(
                      icon: PlatformInfo.isIOS26OrHigher()
                          ? 'ellipsis'
                          : Icons.more_vert,
                      onSelected: (index, entry) async {
                        switch (entry.value) {
                          case 'share':
                            await showAppBottomSheet(
                              context: context,
                              builder: (_) => ShareNoteSheet(noteId: widget.noteId),
                            );
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
                        onPressed: () {
                          FocusManager.instance.primaryFocus?.unfocus();
                          SystemChannels.textInput.invokeMethod('TextInput.hide');
                        },
                      ),
                  ],
                ),
                delegate: NoteEditorDelegate(
                  emptyNoteExit: (noteId) => defaultEmptyNoteExit(repo, noteId),
                  onTaskLongPress: isReadOnly
                      ? null
                      : (task, flushSnapshot) =>
                          _openTaskActions(task, flushSnapshot),
                  onTaskComplete: (taskId) =>
                      TaskSnackBarHelper.completeTaskWithFeedback(
                    onComplete: () =>
                        ref.read(tasksRepositoryProvider).completeTask(taskId),
                    onUndo: () =>
                        ref.read(tasksRepositoryProvider).reopenTask(taskId),
                  ),
                  onTaskReopen: (taskId) =>
                      ref.read(tasksRepositoryProvider).reopenTask(taskId),
                  onUploadFile: isReadOnly
                      ? null
                      : (id, noteId, filePath, mimeType) =>
                          ref.read(attachmentsRepositoryProvider).upload(
                            id: id,
                            noteId: noteId,
                            file: File(filePath),
                            mimeType: mimeType,
                          ),
                ),
              ),
            );
          },
          loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (error, _) => Scaffold(body: Center(child: Text('Error: $error'))),
        );
      },
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => Scaffold(body: Center(child: Text('Error: $error'))),
    );
  }
}