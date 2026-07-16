library;

import 'dart:async';

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supanotes/features/tasks/presentation/widgets/task_metadata_sheet.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:super_editor/super_editor.dart';

import 'package:supanotes/shared/widgets/app_bottom_sheet.dart';
import 'package:supanotes/shared/widgets/app_popup_menu.dart';
import 'package:supanotes/core/auth/current_user.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/features/notes/data/notes_repository.dart';
import 'package:supanotes/features/notes/data/user_note_preferences_repository.dart';
import 'package:supanotes/features/notes/domain/note_model.dart';
import 'package:supanotes/features/notes/domain/note_strings.dart';
import 'package:supanotes/features/notes/presentation/controllers/note_editor_delegate.dart';
import 'package:supanotes/features/notes/presentation/controllers/note_editor_provider.dart';
import 'package:supanotes/features/notes/presentation/controllers/notes_providers.dart';
import 'package:supanotes/features/notes/presentation/widgets/note_editor.dart';
import 'package:supanotes/features/notes/presentation/widgets/share_note_sheet.dart';
import 'package:supanotes/features/tasks/data/tasks_repository.dart';
import 'package:supanotes/features/tasks/domain/task_model.dart';
import 'package:supanotes/features/tasks/presentation/controllers/task_snackbar_helper.dart';

class NoteEditorScreen extends ConsumerStatefulWidget {
  final String noteId;

  const NoteEditorScreen({super.key, required this.noteId});

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  Widget _fallbackScaffold(Widget child) => AdaptiveScaffold(
    body: SafeArea(child: Center(child: child)),
  );

  Future<void> _openTaskActions(
    TaskModel? task,
    Future<void> Function() flushSnapshot,
  ) async {
    await flushSnapshot();
    if (!mounted || task == null) return;

    await TaskMetadataSheet.show(context, noteId: task.noteId, task: task);
  }

  Future<void> _showMoreMenu(
    BuildContext context,
    WidgetRef ref,
    NoteModel note,
    bool hideCompleted,
    INotesRepository repo,
  ) async {
    final isOwner = note.isOwner;
    final val = await showAdaptivePopupMenu<String>(
      context: context,
      items: [
        if (isOwner)
          AdaptivePopupMenuItem<String>(
            label: NoteStrings.shareLabel,
            icon: Icons.share_outlined,
            value: 'share',
          ),
        AdaptivePopupMenuItem<String>(
          label: hideCompleted
              ? NoteStrings.showCompleted
              : NoteStrings.hideCompleted,
          icon: hideCompleted ? Icons.visibility : Icons.visibility_off,
          value: 'hide_completed',
        ),
        if (isOwner)
          AdaptivePopupMenuItem<String>(
            label: note.collapseImages
                ? 'Expandir imagens'
                : 'Colapsar imagens',
            icon: note.collapseImages ? Icons.image : Icons.image_outlined,
            value: 'collapse_images',
          ),
      ],
    );
    if (val != null && context.mounted) {
      _handleMenuValue(context, ref, val, note, hideCompleted, repo);
    }
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
    final noteWithTasksAsync = ref.watch(
      noteWithTasksProvider(widget.noteId),
    );

    return noteWithTasksAsync.when(
      data: (noteWithTasks) {
        final note = noteWithTasks.note;
        if (note == null) {
          return _fallbackScaffold(Text(NoteStrings.errorNotFound));
        }

        final tasksMap = noteWithTasks.taskById;

        final isReadOnly = note.isReadOnly;
        final hideCompleted = note.hideCompleted;

        return AdaptiveScaffold(
          appBar: /* AppBar(
            actions: [
              IconButton(
                onPressed: () {
                  _showMoreMenu(context, ref, note, hideCompleted, repo);
                },
                icon: Icon(Icons.more_vert),
              ),
              if (!isReadOnly)
                IconButton(
                  icon: Icon(Icons.check),
                  onPressed: () {
                    FocusManager.instance.primaryFocus?.unfocus();
                    SystemChannels.textInput.invokeMethod('TextInput.hide');
                  },
                ),
            ],
          ), */ AdaptiveAppBar(
            title: isReadOnly
                ? '${NoteStrings.sharedByPrefix} ${note.sharedByEmail}'
                : null,
            actions: [
              AdaptiveAppBarAction(
                icon: Icons.more_vert,
                iosSymbol: 'ellipsis',
                onPressed: () =>
                    _showMoreMenu(context, ref, note, hideCompleted, repo),
              ),
              if (!isReadOnly)
                AdaptiveAppBarAction(
                  icon: Icons.check,
                  iosSymbol: 'checkmark',
                  onPressed: () {
                    FocusManager.instance.primaryFocus?.unfocus();
                    SystemChannels.textInput.invokeMethod('TextInput.hide');
                  },
                ),
            ],
          ),
          body: SafeArea(
            top: false,
            bottom: false,
            child: NoteEditor(
              noteId: widget.noteId,
              nodes: const [],
              taskMetadata: tasksMap,
              hideCompleted: hideCompleted,
              collapseImages: note.collapseImages,
              isReadOnly: isReadOnly,
              delegate: NoteEditorDelegate(
                onTaskLongPress: isReadOnly
                    ? null
                    : (task, flushSnapshot) =>
                          _openTaskActions(task, flushSnapshot),
                onTaskComplete: (taskId) =>
                    TaskSnackBarHelper.completeTaskWithFeedback(
                      onComplete: () => ref
                          .read(tasksRepositoryProvider)
                          .completeTask(taskId),
                      onUndo: (previousDue) {
                        final controller = ref.read(
                          noteEditorControllerProvider(widget.noteId),
                        );
                        if (previousDue != null) {
                          controller.updateTaskMetadataInYDoc(
                            taskId,
                            dueDate: previousDue,
                          );
                        }
                        controller.editor?.execute([
                          ChangeTaskCompletionRequest(
                            nodeId: taskId,
                            isComplete: false,
                          ),
                        ]);
                        ref
                            .read(appDatabaseProvider)
                            .taskCompletionsDao
                            .undoLastCompletion(taskId);
                      },
                    ),
                onTaskReopen: (taskId) =>
                    ref.read(tasksRepositoryProvider).reopenTask(taskId),
          ),
            ),
          ),
        );
      },
      loading: () => _fallbackScaffold(const CircularProgressIndicator()),
      error: (error, _) => _fallbackScaffold(Text('Error: $error')),
    );
  }
}
