library;

import 'dart:async';
import 'dart:ui';

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:super_editor/super_editor.dart';
import 'package:supanotes/features/tasks/presentation/widgets/task_metadata_sheet.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:supanotes/core/router/app_routes.dart';
import 'package:supanotes/shared/widgets/app_bottom_sheet.dart';
import 'package:supanotes/features/notes/catalog/model/note_model.dart';
import 'package:supanotes/features/notes/catalog/model/note_strings.dart';
import 'package:supanotes/features/notes/editor/application/note_editor_delegate.dart';
import 'package:supanotes/features/notes/editor/application/note_editor_provider.dart';
import 'package:supanotes/features/notes/preferences/application/note_preferences_mutation_controller.dart';
import 'package:supanotes/features/notes/catalog/application/notes_providers.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/desktop_editor_viewport.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/desktop_note_chrome.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/note_editor.dart';
import 'package:supanotes/features/notes/sharing/presentation/share_note_sheet.dart';
import 'package:supanotes/features/tasks/presentation/controllers/task_snackbar_helper.dart';
import 'package:supanotes/features/tasks/domain/task_model.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';

import 'package:supanotes/core/utils/platform_utils.dart';

class NoteEditorScreen extends ConsumerStatefulWidget {
  final String noteId;
  final bool requestInitialFocus;

  const NoteEditorScreen({
    super.key,
    required this.noteId,
    this.requestInitialFocus = false,
  });

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
        .read(noteEditorSessionProvider(widget.noteId))
        .value
        ?.controller;
    final node = controller?.document.getNodeById(taskId);
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
  ) async {
    final mutationController = ref.read(
      notePreferenceMutationControllerProvider(widget.noteId).notifier,
    );
    switch (value) {
      case 'share':
        await showAppBottomSheet(
          context: context,
          builder: (_) => ShareNoteSheet(noteId: widget.noteId),
        );
      case 'hide_completed':
        await mutationController.setHideCompleted(
          current: note,
          value: !hideCompleted,
        );
      case 'collapse_images':
        await mutationController.setCollapseImages(
          current: note,
          value: !note.collapseImages,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final noteWithTasksAsync = ref.watch(noteWithTasksProvider(widget.noteId));
    final note = noteWithTasksAsync.when(
      data: (noteWithTasks) => noteWithTasks.note,
      loading: () => null,
      error: (_, _) => null,
    );
    final preferenceMutation = ref.watch(
      notePreferenceMutationControllerProvider(widget.noteId),
    );
    final sessionAsync = ref.watch(noteEditorSessionProvider(widget.noteId));

    final isDesktop = isDesktopLayout(context);
    final editorFocusNode = sessionAsync.when(
      data: (session) => session.controller.focusNode,
      loading: () => null,
      error: (_, _) => null,
    );

    return Scaffold(
      backgroundColor: isDesktop ? Colors.transparent : null,
      extendBodyBehindAppBar: !isDesktop,
      appBar: isDesktop
          ? null
          : AppBar(
              automaticallyImplyLeading: false,
              leading: !isDesktop
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () {
                        if (context.canPop()) {
                          context.pop();
                        } else {
                          context.go(AppRoutes.home);
                        }
                      },
                    )
                  : null,
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
                    icon: PlatformInfo.isIOS26OrHigher()
                        ? 'ellipsis'
                        : Icons.more_vert,
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
                        );
                      }
                    },
                  ),
                  if (preferenceMutation.status ==
                      NotePreferenceMutationStatus.saving)
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: Padding(
                        padding: EdgeInsets.all(4),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else if (preferenceMutation.status ==
                      NotePreferenceMutationStatus.error)
                    const Icon(Icons.error_outline),
                  if (!note.isReadOnly)
                    sessionAsync.when(
                      data: (session) => AnimatedBuilder(
                        animation: session.controller.focusNode,
                        builder: (context, _) {
                          if (!session.controller.focusNode.hasFocus) {
                            return const SizedBox.shrink();
                          }
                          return IconButton(
                            icon: const Icon(Icons.check),
                            onPressed: () {
                              session.controller.focusNode.unfocus();
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
      body: Column(
        children: [
          if (isDesktop)
            DesktopNoteChrome(
              note: note,
              preferenceStatus: preferenceMutation.status,
              editorFocusNode: editorFocusNode,
              onMenuSelected: (value) {
                final currentNote = note;
                if (currentNote == null) return;
                _handleMenuValue(
                  context,
                  ref,
                  value,
                  currentNote,
                  currentNote.hideCompleted,
                );
              },
              onExitFocus: () {
                editorFocusNode?.unfocus();
                SystemChannels.textInput.invokeMethod('TextInput.hide');
              },
            ),
          Expanded(
            child: SafeArea(
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
                  final editor = NoteEditor(
                    noteId: widget.noteId,
                    requestInitialFocus: widget.requestInitialFocus,
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
                                            noteEditorSessionProvider(
                                              widget.noteId,
                                            ),
                                          )
                                          .value
                                          ?.controller;
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
                                .read(noteEditorSessionProvider(widget.noteId))
                                .value
                                ?.controller;
                            if (controller == null) {
                              return (
                                nextDue: null,
                                previousDue: null,
                                previousHasTime: false,
                                scheduledAt: null,
                              );
                            }
                            final result = controller.completeTaskInEditor(
                              taskId,
                            );
                            return (
                              nextDue: result?.nextDue,
                              previousDue: result?.previousDue,
                              previousHasTime: result?.previousHasTime ?? false,
                              scheduledAt: result?.scheduledAt,
                            );
                          },
                          onUndo: (previousDue, previousHasTime, scheduledAt) {
                            final controller = ref
                                .read(noteEditorSessionProvider(widget.noteId))
                                .value
                                ?.controller;
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
                            .read(noteEditorSessionProvider(widget.noteId))
                            .value
                            ?.controller;
                        if (controller != null) {
                          controller.reopenTaskInEditor(taskId);
                        }
                      },
                    ),
                  );
                  return isDesktop
                      ? DesktopEditorViewport(child: editor)
                      : editor;
                },
                loading: () => const SizedBox.shrink(),
                error: (error, _) => Center(child: Text('Error: $error')),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
