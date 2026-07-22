library;

import 'dart:async';
import 'dart:ui';

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:super_editor/super_editor.dart';
import 'package:supanotes/features/tasks/presentation/widgets/task_metadata_sheet.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/shared/widgets/app_bottom_sheet.dart';
import 'package:supanotes/core/auth/current_user.dart';
import 'package:supanotes/features/notes/data/notes_repository.dart';
import 'package:supanotes/features/notes/data/user_note_preferences_repository.dart';
import 'package:supanotes/features/notes/domain/note_model.dart';
import 'package:supanotes/features/notes/domain/note_strings.dart';
import 'package:supanotes/features/notes/presentation/controllers/note_editor_delegate.dart';
import 'package:supanotes/features/notes/presentation/controllers/note_editor_provider.dart';
import 'package:supanotes/features/notes/presentation/controllers/notes_providers.dart';
import 'package:supanotes/features/notes/presentation/widgets/note_editor.dart';
import 'package:supanotes/features/notes/presentation/widgets/share_note_sheet.dart';
import 'package:supanotes/features/tasks/presentation/controllers/task_snackbar_helper.dart';
import 'package:supanotes/features/tasks/domain/task_model.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';

class NoteEditorScreen extends ConsumerStatefulWidget {
  final String noteId;

  const NoteEditorScreen({super.key, required this.noteId});

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  TaskModel? _taskForMetadata(
    String taskId,
    Map<String, TaskModel> tasks,
    NoteModel note,
  ) {
    final projected = tasks[taskId];
    if (projected != null) return projected;

    final controller = ref
        .read(noteEditorControllerProvider(widget.noteId))
        .value;
    final node = controller?.document?.getNodeById(taskId);
    if (node is! TaskNode) return null;

    final dueDate = DateTime.tryParse(
      node.metadata['dueDate'] as String? ?? '',
    );
    return TaskModel(
      id: node.id,
      userId: note.userId,
      noteId: note.id,
      title: node.text.toPlainText(),
      status: node.isComplete ? 'done' : 'open',
      position: '',
      dueDate: dueDate,
      hasTime: node.metadata['hasTime'] as bool? ?? false,
      completedAt: null,
      recurrence: TaskRecurrence.parse(
        node.metadata['recurrenceRule'] as String? ??
            node.metadata['recurrence'] as String?,
      ),
      reminder: node.metadata['reminder'] as String?,
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    );
  }

  Future<void> _handleMenuValue(
    BuildContext context,
    WidgetRef ref,
    String value,
    NoteModel note,
    bool hideCompleted,
    INotesRepository repo,
  ) async {
    switch (value) {
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
              .setHideCompleted(userId, widget.noteId, !hideCompleted);
        }
      case 'collapse_images':
        await repo.updateNote(
          widget.noteId,
          collapseImages: !note.collapseImages,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(notesRepositoryProvider);
    final noteWithTasksAsync = ref.watch(noteWithTasksProvider(widget.noteId));
    final controllerAsync = ref.watch(
      noteEditorControllerProvider(widget.noteId),
    );
    final note = noteWithTasksAsync.asData?.value.note;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
            child: Container(color: Colors.transparent),
          ),
        ),
        title: note?.isReadOnly == true
            ? Text('${NoteStrings.sharedByPrefix} ${note!.sharedByEmail}')
            : null,
        actions: [
          if (note != null) ...[
            AdaptivePopupMenuButton.icon<String>(
              icon: PlatformInfo.isIOS26OrHigher() ? 'ellipsis' : Icons.more_vert,
              items: [
                if (note.isOwner)
                  AdaptivePopupMenuItem<String>(
                    label: NoteStrings.shareLabel,
                    icon: PlatformInfo.isIOS26OrHigher()
                        ? 'square.and.arrow.up'
                        : Icons.share_outlined,
                    value: 'share',
                  ),
                AdaptivePopupMenuItem<String>(
                  label: note.hideCompleted
                      ? NoteStrings.showCompleted
                      : NoteStrings.hideCompleted,
                  icon: PlatformInfo.isIOS26OrHigher()
                      ? (note.hideCompleted ? 'eye' : 'eye.slash')
                      : (note.hideCompleted
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined),
                  value: 'hide_completed',
                ),
                if (note.isOwner)
                  AdaptivePopupMenuItem<String>(
                    label: note.collapseImages
                        ? 'Expandir imagens'
                        : 'Colapsar imagens',
                    icon: PlatformInfo.isIOS26OrHigher()
                        ? 'photo'
                        : Icons.image_outlined,
                    value: 'collapse_images',
                  ),
              ],
              onSelected: (index, entry) {
                final value = entry.value;
                if (value != null) {
                  _handleMenuValue(
                    context,
                    ref,
                    value,
                    note,
                    note.hideCompleted,
                    repo,
                  );
                }
              },
            ),
            if (!note.isReadOnly)
              controllerAsync.when(
                data: (controller) => AnimatedBuilder(
                  animation: controller.focusNode,
                  builder: (context, _) {
                    if (!controller.focusNode.hasFocus) {
                      return const SizedBox.shrink();
                    }
                    return IconButton(
                      icon: const Icon(Icons.check),
                      onPressed: () {
                        controller.focusNode.unfocus();
                        SystemChannels.textInput.invokeMethod('TextInput.hide');
                      },
                    );
                  },
                ),
                loading: () => const SizedBox.shrink(),
                error: (_, _) => const SizedBox.shrink(),
              ),
          ],
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: noteWithTasksAsync.when(
          data: (noteWithTasks) {
            final tasksMap = noteWithTasks.taskById;
            final noteData = noteWithTasks.note;
            if (noteData == null) {
              return Center(child: Text(NoteStrings.errorNotFound));
            }

            final isReadOnly = noteData.isReadOnly;
            return NoteEditor(
              noteId: widget.noteId,
              taskMetadata: tasksMap,
              hideCompleted: noteData.hideCompleted,
              collapseImages: noteData.collapseImages,
              isReadOnly: isReadOnly,
              delegate: NoteEditorDelegate(
                onTaskLongPress: isReadOnly
                    ? null
                    : (taskId) async {
                        final task = _taskForMetadata(
                          taskId,
                          tasksMap,
                          noteData,
                        );
                        if (!context.mounted || task == null) return;
                        await showTaskMetadataSheet(
                          context: context,
                          ref: ref,
                          noteId: noteData.id,
                          task: task,
                          onSave:
                              ({
                                required dueDate,
                                required hasTime,
                                required recurrence,
                                required reminder,
                              }) async {
                                final controller = ref
                                    .read(
                                      noteEditorControllerProvider(
                                        widget.noteId,
                                      ),
                                    )
                                    .value;
                                controller?.updateTaskMetadataInEditor(
                                  taskId,
                                  dueDate: dueDate,
                                  clearDueDate: dueDate == null,
                                  hasTime: hasTime,
                                  recurrence: recurrence?.name,
                                  clearRecurrence: recurrence == null,
                                  reminder: reminder,
                                  clearReminder: reminder == null,
                                );
                              },
                        );
                      },
                onTaskComplete: (taskId) {
                  return TaskSnackBarHelper.completeTaskWithFeedback(
                    onComplete: () async {
                      final controller = ref
                          .read(noteEditorControllerProvider(widget.noteId))
                          .value;
                      if (controller == null) {
                        return (
                          nextDue: null,
                          previousDue: null,
                          previousHasTime: false,
                          scheduledAt: null,
                        );
                      }
                      final result = controller.completeTaskInEditor(taskId);
                      return (
                        nextDue: result?.nextDue,
                        previousDue: result?.previousDue,
                        previousHasTime: result?.previousHasTime ?? false,
                        scheduledAt: result?.scheduledAt,
                      );
                    },
                    onUndo: (previousDue, previousHasTime, scheduledAt) {
                      final controller = ref
                          .read(noteEditorControllerProvider(widget.noteId))
                          .value;
                      if (controller != null) {
                        // For recurring tasks, the template's dueDate is the
                        // anchor and never changes — only remove the completion.
                        controller.reopenTaskInEditor(
                          taskId,
                          previousDue: previousDue,
                          scheduledAt: scheduledAt,
                        );
                      }
                    },
                  );
                },
                onTaskReopen: (taskId) async {
                  final controller = ref
                      .read(noteEditorControllerProvider(widget.noteId))
                      .value;
                  if (controller != null) {
                    controller.reopenTaskInEditor(taskId);
                  }
                },
              ),
            );
          },
          loading: () => const SizedBox.shrink(),
          error: (error, _) => Center(child: Text('Error: $error')),
        ),
      ),
    );
  }
}
