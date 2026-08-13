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
import 'package:supanotes/features/tasks/presentation/controllers/task_metadata_draft.dart';
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
  TaskMetadataDraft? _taskForMetadata(String taskId) {
    final controller = _readSession().value?.controller;
    final node = controller?.document.getNodeById(taskId);
    if (node is! TaskNode) return null;
    return TaskMetadataDraft.fromTaskNode(node);
  }

  AsyncValue<NoteEditorSession> _readSession() =>
      ref.read(noteEditorSessionProvider(widget.noteId));

  @override
  Widget build(BuildContext context) {
    final noteAsync = ref.watch(noteProvider(widget.noteId));
    final note = noteAsync.when(
      data: (note) => note,
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
        noteAsync: noteAsync,
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

class _NoteEditorBody extends StatelessWidget {
  const _NoteEditorBody({
    required this.noteId,
    required this.attachmentDelivery,
    required this.noteAsync,
    required this.sessionAsync,
    required this.taskForMetadata,
    required this.readSession,
  });

  final String noteId;
  final AttachmentDelivery? attachmentDelivery;
  final AsyncValue<NoteModel?> noteAsync;
  final AsyncValue<NoteEditorSession> sessionAsync;
  final TaskMetadataDraft? Function(String taskId) taskForMetadata;
  final AsyncValue<NoteEditorSession> Function() readSession;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SafeArea(
            top: false,
            bottom: false,
            child: _NoteEditorDocument(
              noteId: noteId,
              attachmentDelivery: attachmentDelivery,
              noteAsync: noteAsync,
              sessionAsync: sessionAsync,
              taskForMetadata: taskForMetadata,
              readSession: readSession,
            ),
          ),
        ),
      ],
    );
  }
}

class _NoteEditorDocument extends StatelessWidget {
  const _NoteEditorDocument({
    required this.noteId,
    required this.attachmentDelivery,
    required this.noteAsync,
    required this.sessionAsync,
    required this.taskForMetadata,
    required this.readSession,
  });

  final String noteId;
  final AttachmentDelivery? attachmentDelivery;
  final AsyncValue<NoteModel?> noteAsync;
  final AsyncValue<NoteEditorSession> sessionAsync;
  final TaskMetadataDraft? Function(String taskId) taskForMetadata;
  final AsyncValue<NoteEditorSession> Function() readSession;

  @override
  Widget build(BuildContext context) {
    return noteAsync.when(
      data: (note) {
        if (note == null) {
          return Center(child: Text(NoteStrings.errorNotFound));
        }
        return _NoteEditorSessionContent(
          noteId: noteId,
          note: note,
          attachmentDelivery: attachmentDelivery,
          sessionAsync: sessionAsync,
          taskForMetadata: taskForMetadata,
          readSession: readSession,
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const AppErrorView(title: NoteStrings.editorErrorTitle),
    );
  }
}

class _NoteEditorSessionContent extends StatelessWidget {
  const _NoteEditorSessionContent({
    required this.noteId,
    required this.note,
    required this.attachmentDelivery,
    required this.sessionAsync,
    required this.taskForMetadata,
    required this.readSession,
  });

  final String noteId;
  final NoteModel note;
  final AttachmentDelivery? attachmentDelivery;
  final AsyncValue<NoteEditorSession> sessionAsync;
  final TaskMetadataDraft? Function(String taskId) taskForMetadata;
  final AsyncValue<NoteEditorSession> Function() readSession;

  @override
  Widget build(BuildContext context) {
    return sessionAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const AppErrorView(title: NoteStrings.editorErrorTitle),
      data: (session) => _NoteEditorWithSession(
        noteId: noteId,
        note: note,
        attachmentDelivery: attachmentDelivery,
        session: session,
        taskForMetadata: taskForMetadata,
        readSession: readSession,
      ),
    );
  }
}

class _NoteEditorWithSession extends ConsumerWidget {
  const _NoteEditorWithSession({
    required this.noteId,
    required this.note,
    required this.attachmentDelivery,
    required this.session,
    required this.taskForMetadata,
    required this.readSession,
  });

  final String noteId;
  final NoteModel note;
  final AttachmentDelivery? attachmentDelivery;
  final NoteEditorSession session;
  final TaskMetadataDraft? Function(String taskId) taskForMetadata;
  final AsyncValue<NoteEditorSession> Function() readSession;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final taskDelegate = _NoteEditorTaskDelegate(
      context: context,
      ref: ref,
      note: note,
      taskForMetadata: taskForMetadata,
      readSession: readSession,
      isReadOnly: !session.captureLocalOperations,
    );
    return NoteEditor(
      noteId: noteId,
      session: session,
      requestInitialFocus: note.shouldAutofocus,
      hideCompleted: note.hideCompleted,
      collapseImages: note.collapseImages,
      attachmentDelivery: attachmentDelivery,
      delegate: taskDelegate.create(),
    );
  }
}

class _NoteEditorTaskDelegate {
  const _NoteEditorTaskDelegate({
    required this.context,
    required this.ref,
    required this.note,
    required this.taskForMetadata,
    required this.readSession,
    required this.isReadOnly,
  });

  final BuildContext context;
  final WidgetRef ref;
  final NoteModel note;
  final TaskMetadataDraft? Function(String taskId) taskForMetadata;
  final AsyncValue<NoteEditorSession> Function() readSession;
  final bool isReadOnly;

  NoteEditorDelegate create() {
    if (isReadOnly) return const NoteEditorDelegate();
    return NoteEditorDelegate(
      onTaskLongPress: _onTaskLongPress,
      onTaskComplete: _onTaskComplete,
      onTaskReopen: _onTaskReopen,
    );
  }

  Future<void> _onTaskLongPress(String taskId) async {
    final task = taskForMetadata(taskId);
    if (!context.mounted || task == null) return;
    await showTaskMetadataSheet(
      context: context,
      ref: ref,
      taskId: taskId,
      draft: task,
      onSave: (draft) => _saveTaskMetadata(taskId, draft),
    );
  }

  Future<void> _saveTaskMetadata(String taskId, TaskMetadataDraft draft) async {
    final controller = readSession().value?.controller;
    controller?.updateTaskMetadataInEditor(
      taskId,
      dueDate: draft.scheduleAnchor,
      clearDueDate: draft.scheduleAnchor == null,
      hasTime: draft.hasTime,
      recurrence: draft.recurrence?.name,
      clearRecurrence: draft.recurrence == null,
      reminder: draft.reminder?.value,
      clearReminder: draft.reminder == null,
    );
  }

  Future<DateTime?> _onTaskComplete(String taskId) {
    return TaskSnackBarHelper.completeTaskWithFeedback(
      onComplete: () async {
        final controller = readSession().value?.controller;
        final result = controller?.completeTaskInEditor(taskId);
        return (
          nextDue: result?.nextDue,
          previousDue: result?.previousDue,
          previousHasTime: result?.previousHasTime ?? false,
          scheduledAt: result?.scheduledAt,
        );
      },
      onUndo: (previousDue, _, scheduledAt) {
        final controller = readSession().value?.controller;
        if (controller != null) {
          // For recurring tasks, the template's dueDate is the anchor and
          // never changes — only remove the completion.
          controller.reopenTaskInEditor(
            taskId,
            previousDue: previousDue,
            scheduledAt: scheduledAt,
          );
        }
      },
    );
  }

  Future<void> _onTaskReopen(String taskId) async {
    final controller = readSession().value?.controller;
    controller?.reopenTaskInEditor(taskId);
  }
}
