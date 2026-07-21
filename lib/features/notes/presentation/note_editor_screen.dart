library;

import 'dart:async';
import 'dart:ui';

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

class NoteEditorScreen extends ConsumerStatefulWidget {
  final String noteId;

  const NoteEditorScreen({super.key, required this.noteId});

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
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
    final controllerAsync = ref.watch(noteEditorControllerProvider(widget.noteId));
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
              icon: Icons.more_vert,
              items: [
                if (note.isOwner)
                  const AdaptivePopupMenuItem<String>(
                    label: NoteStrings.shareLabel,
                    icon: CupertinoIcons.share,
                    value: 'share',
                  ),
                AdaptivePopupMenuItem<String>(
                  label: note.hideCompleted
                      ? NoteStrings.showCompleted
                      : NoteStrings.hideCompleted,
                  icon: note.hideCompleted
                      ? CupertinoIcons.eye_solid
                      : CupertinoIcons.eye_slash_fill,
                  value: 'hide_completed',
                ),
                if (note.isOwner)
                  AdaptivePopupMenuItem<String>(
                    label: note.collapseImages
                        ? 'Expandir imagens'
                        : 'Colapsar imagens',
                    icon: note.collapseImages
                        ? Icons.image
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
                        SystemChannels.textInput.invokeMethod(
                          'TextInput.hide',
                        );
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
                    : (task, flushSnapshot) async {
                        await flushSnapshot();
                        if (!context.mounted || task == null) return;
                        await showTaskMetadataSheet(
                          context: context,
                          ref: ref,
                          noteId: noteData.id,
                          task: task,
                        );
                      },
                onTaskComplete: (taskId) =>
                    TaskSnackBarHelper.completeTaskWithFeedback(
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
                    final result = controller.completeTaskInYDoc(taskId);
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
                      controller.updateTaskMetadataInYDoc(
                        taskId,
                        dueDate: previousDue,
                        clearDueDate: previousDue == null,
                        hasTime: previousHasTime,
                      );
                      controller.reopenTaskInYDoc(
                        taskId,
                        previousDue: previousDue,
                        scheduledAt: scheduledAt,
                      );
                    }
                  },
                ),
                onTaskReopen: (taskId) async {
                  final controller = ref
                      .read(noteEditorControllerProvider(widget.noteId))
                      .value;
                  if (controller != null) {
                    controller.reopenTaskInYDoc(taskId);
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
