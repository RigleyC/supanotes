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
import 'package:supanotes/features/notes/catalog/model/note_with_tasks.dart';
import 'package:supanotes/features/notes/attachments/domain/attachment_delivery.dart';
import 'package:supanotes/features/notes/catalog/model/note_strings.dart';
import 'package:supanotes/features/notes/editor/application/note_editor_delegate.dart';
import 'package:supanotes/features/notes/editor/application/note_editor_provider.dart';
import 'package:supanotes/features/notes/editor/application/note_editor_session.dart';
import 'package:supanotes/features/notes/preferences/application/note_preferences_mutation_controller.dart';
import 'package:supanotes/features/notes/catalog/application/notes_providers.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/note_editor.dart';
import 'package:supanotes/features/notes/sharing/presentation/share_note_sheet.dart';
import 'package:supanotes/features/tasks/presentation/controllers/task_snackbar_helper.dart';
import 'package:supanotes/features/tasks/domain/task_model.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';
import 'package:supanotes/shared/widgets/app_error_view.dart';

class NoteEditorScreen extends ConsumerStatefulWidget {
  final String noteId;
  final AttachmentDelivery? attachmentDelivery;

  const NoteEditorScreen({
    super.key,
    required this.noteId,
    this.attachmentDelivery,
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

    final controller = _readSession().value?.controller;
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

  AsyncValue<NoteEditorSession> _readSession() =>
      ref.read(noteEditorSessionProvider(widget.noteId));

  @override
  Widget build(BuildContext context) {
    final noteWithTasksAsync = ref.watch(noteWithTasksProvider(widget.noteId));
    final note = noteWithTasksAsync.when(
      data: (noteWithTasks) => noteWithTasks.note,
      loading: () => null,
      error: (_, _) => null,
    );
    final sessionAsync = ref.watch(noteEditorSessionProvider(widget.noteId));
    final captureAsync = ref.watch(noteEditorCaptureProvider(widget.noteId));
    final screenIsReadOnly = captureAsync.when(
      data: (capture) => !capture,
      loading: () => note?.isReadOnly ?? true,
      error: (_, _) => true,
    );
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: _NoteEditorAppBar(
        noteId: widget.noteId,
        note: note,
        screenIsReadOnly: screenIsReadOnly,
        sessionAsync: sessionAsync,
      ),
      body: _NoteEditorBody(
        noteId: widget.noteId,
        attachmentDelivery: widget.attachmentDelivery,
        noteWithTasksAsync: noteWithTasksAsync,
        sessionAsync: sessionAsync,
        taskForMetadata: _taskForMetadata,
        readSession: _readSession,
      ),
    );
  }
}

class _NoteEditorAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const _NoteEditorAppBar({
    required this.noteId,
    required this.note,
    required this.screenIsReadOnly,
    required this.sessionAsync,
  });

  final String noteId;
  final NoteModel? note;
  final bool screenIsReadOnly;
  final AsyncValue<NoteEditorSession> sessionAsync;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentNote = note;

    return AppBar(
      automaticallyImplyLeading: false,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go(AppRoutes.home);
          }
        },
      ),
      flexibleSpace: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
          child: Container(color: Colors.transparent),
        ),
      ),
      title: screenIsReadOnly && currentNote?.sharedByEmail != null
          ? Text('${NoteStrings.sharedByPrefix} ${currentNote!.sharedByEmail}')
          : null,
      actions: currentNote == null || screenIsReadOnly
          ? const []
          : [
              _NoteEditorMenuButton(noteId: noteId, note: currentNote),
              _NoteEditorPreferenceStatus(noteId: noteId),
              _NoteEditorKeyboardButton(sessionAsync: sessionAsync),
            ],
    );
  }
}

class _NoteEditorMenuButton extends ConsumerWidget {
  const _NoteEditorMenuButton({required this.noteId, required this.note});

  final String noteId;
  final NoteModel note;

  Future<void> _handleSelection(
    BuildContext context,
    WidgetRef ref,
    String value,
  ) async {
    final session = ref.read(noteEditorSessionProvider(noteId)).value;
    if (session == null || !session.captureLocalOperations) return;

    final mutationController = ref.read(
      notePreferenceMutationControllerProvider(noteId).notifier,
    );
    switch (value) {
      case 'share':
        await showAppBottomSheet(
          context: context,
          builder: (_) => ShareNoteSheet(noteId: noteId),
        );
      case 'hide_completed':
        await mutationController.setHideCompleted(
          current: note,
          value: !note.hideCompleted,
        );
      case 'collapse_images':
        await mutationController.setCollapseImages(
          current: note,
          value: !note.collapseImages,
        );
    }
  }

  List<AdaptivePopupMenuItem<String>> _buildItems(bool isIos) {
    return [
      if (note.isOwner) _shareItem(isIos),
      _completedTasksItem(isIos),
      if (note.isOwner) _collapseImagesItem(isIos),
    ];
  }

  AdaptivePopupMenuItem<String> _shareItem(bool isIos) {
    return AdaptivePopupMenuItem<String>(
      label: NoteStrings.shareLabel,
      icon: isIos ? 'square.and.arrow.up' : Icons.share_outlined,
      value: 'share',
    );
  }

  AdaptivePopupMenuItem<String> _completedTasksItem(bool isIos) {
    return AdaptivePopupMenuItem<String>(
      label: note.hideCompleted
          ? NoteStrings.showCompleted
          : NoteStrings.hideCompleted,
      icon: isIos
          ? (note.hideCompleted ? 'eye' : 'eye.slash')
          : (note.hideCompleted
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined),
      value: 'hide_completed',
    );
  }

  AdaptivePopupMenuItem<String> _collapseImagesItem(bool isIos) {
    return AdaptivePopupMenuItem<String>(
      label: note.collapseImages ? 'Expandir imagens' : 'Colapsar imagens',
      icon: isIos ? 'photo' : Icons.image_outlined,
      value: 'collapse_images',
    );
  }

  void _onSelected(
    BuildContext context,
    WidgetRef ref,
    AdaptivePopupMenuItem<String> entry,
  ) {
    final value = entry.value;
    if (value != null) {
      _handleSelection(context, ref, value);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isIos = PlatformInfo.isIOS26OrHigher();
    return AdaptivePopupMenuButton.icon<String>(
      icon: isIos ? 'ellipsis' : Icons.more_vert,
      items: _buildItems(isIos),
      onSelected: (_, entry) => _onSelected(context, ref, entry),
    );
  }
}

class _NoteEditorPreferenceStatus extends ConsumerWidget {
  const _NoteEditorPreferenceStatus({required this.noteId});

  final String noteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref
        .watch(notePreferenceMutationControllerProvider(noteId))
        .status;
    if (status == NotePreferenceMutationStatus.saving) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: Padding(
          padding: EdgeInsets.all(4),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (status == NotePreferenceMutationStatus.error) {
      return const Icon(Icons.error_outline);
    }
    return const SizedBox.shrink();
  }
}

class _NoteEditorKeyboardButton extends StatelessWidget {
  const _NoteEditorKeyboardButton({required this.sessionAsync});

  final AsyncValue<NoteEditorSession> sessionAsync;

  @override
  Widget build(BuildContext context) {
    return sessionAsync.when(
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
              SystemChannels.textInput.invokeMethod('TextInput.hide');
            },
          );
        },
      ),
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}

class _NoteEditorBody extends ConsumerWidget {
  const _NoteEditorBody({
    required this.noteId,
    required this.attachmentDelivery,
    required this.noteWithTasksAsync,
    required this.sessionAsync,
    required this.taskForMetadata,
    required this.readSession,
  });

  final String noteId;
  final AttachmentDelivery? attachmentDelivery;
  final AsyncValue<NoteWithTasks> noteWithTasksAsync;
  final AsyncValue<NoteEditorSession> sessionAsync;
  final TaskModel? Function(
    String taskId,
    Map<String, TaskModel> tasks,
    NoteModel note,
  )
  taskForMetadata;
  final AsyncValue<NoteEditorSession> Function() readSession;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
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

                return sessionAsync.when(
                  loading: () => const SizedBox.shrink(),
                  error: (_, _) =>
                      const AppErrorView(title: NoteStrings.editorErrorTitle),
                  data: (session) {
                    final isReadOnly = !session.captureLocalOperations;
                    final editor = NoteEditor(
                      noteId: noteId,
                      session: session,
                      requestInitialFocus: noteData.shouldAutofocus,
                      taskMetadata: tasksMap,
                      hideCompleted: noteData.hideCompleted,
                      collapseImages: noteData.collapseImages,
                      attachmentDelivery: attachmentDelivery,
                      delegate: NoteEditorDelegate(
                        onTaskLongPress: isReadOnly
                            ? null
                            : (taskId) async {
                                final task = taskForMetadata(
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
                                        final controller =
                                            readSession().value?.controller;
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
                        onTaskComplete: isReadOnly
                            ? null
                            : (taskId) {
                                return TaskSnackBarHelper.completeTaskWithFeedback(
                                  onComplete: () async {
                                    final controller =
                                        readSession().value?.controller;
                                    if (controller == null) {
                                      return (
                                        nextDue: null as DateTime?,
                                        previousDue: null as DateTime?,
                                        previousHasTime: false,
                                        scheduledAt: null as DateTime?,
                                      );
                                    }
                                    final result = controller
                                        .completeTaskInEditor(taskId);
                                    return (
                                      nextDue: result?.nextDue,
                                      previousDue: result?.previousDue,
                                      previousHasTime:
                                          result?.previousHasTime ?? false,
                                      scheduledAt: result?.scheduledAt,
                                    );
                                  },
                                  onUndo: (previousDue, previousHasTime, scheduledAt) {
                                    final controller =
                                        readSession().value?.controller;
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
                        onTaskReopen: isReadOnly
                            ? null
                            : (taskId) async {
                                final controller =
                                    readSession().value?.controller;
                                if (controller != null) {
                                  controller.reopenTaskInEditor(taskId);
                                }
                              },
                      ),
                    );
                    return editor;
                  },
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (_, _) =>
                  const AppErrorView(title: NoteStrings.editorErrorTitle),
            ),
          ),
        ),
      ],
    );
  }
}
