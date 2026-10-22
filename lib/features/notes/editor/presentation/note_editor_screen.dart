import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supanotes/core/router/app_routes.dart';
import 'package:supanotes/features/notes/attachments/data/attachments_repository.dart';
import 'package:supanotes/features/notes/attachments/domain/attachment_delivery.dart';
import 'package:supanotes/features/notes/attachments/domain/attachment_upload.dart';
import 'package:supanotes/features/notes/catalog/application/notes_providers.dart';
import 'package:supanotes/features/notes/catalog/model/note_model.dart';
import 'package:supanotes/features/notes/catalog/model/note_strings.dart';
import 'package:supanotes/features/notes/editor/application/note_editor_delegate.dart';
import 'package:supanotes/features/notes/editor/application/note_editor_provider.dart';
import 'package:supanotes/features/notes/editor/application/note_editor_session.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/note_editor.dart';
import 'package:supanotes/features/notes/preferences/application/note_preferences_mutation_controller.dart';
import 'package:supanotes/features/notes/sharing/presentation/share_note_sheet.dart';
import 'package:supanotes/features/tasks/presentation/controllers/task_metadata_draft.dart';
import 'package:supanotes/features/tasks/presentation/controllers/task_snackbar_helper.dart';
import 'package:supanotes/features/tasks/presentation/widgets/task_metadata_sheet.dart';
import 'package:supanotes/shared/widgets/app_banner.dart';
import 'package:supanotes/shared/widgets/app_bottom_sheet.dart';
import 'package:supanotes/shared/widgets/app_button.dart';
import 'package:supanotes/shared/widgets/app_error_view.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/widgets/app_platform_icon_button.dart';
import 'package:supanotes/shared/widgets/app_popup_menu.dart';
import 'package:super_editor/super_editor.dart';

class NoteEditorScreen extends ConsumerStatefulWidget {
  const NoteEditorScreen({
    required this.noteId,
    super.key,
    this.attachmentDelivery,
    this.blockId,
  });
  final String noteId;
  final AttachmentDelivery? attachmentDelivery;

  /// Optional task block requested by a Tasks deep link.
  ///
  /// It stays in the route query when the block no longer exists, allowing a
  /// later retry after the note has synchronized instead of losing context.
  final String? blockId;

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
    final chromeAsync = ref.watch(
      noteProvider(widget.noteId).select(
        (note) =>
            note.whenData((note) => note == null ? null : _chromeFor(note)),
      ),
    );
    final sessionAsync = ref.watch(noteEditorSessionProvider(widget.noteId));
    final captureAsync = ref.watch(noteEditorCaptureProvider(widget.noteId));
    final isReadOnly = captureAsync.when(
      data: (capture) => !capture,
      loading: () => chromeAsync.when(
        data: (chrome) => chrome?.isReadOnly ?? true,
        loading: () => true,
        error: (_, _) => true,
      ),
      error: (_, _) => true,
    );
    return KeyboardScaffoldSafeArea(
      // Glass surfaces on this screen (the editor toolbar) share one backdrop
      // copy through this group, as the liquid_glass_renderer guide recommends.
      child: BackdropGroup(
        child: Scaffold(
          resizeToAvoidBottomInset: false,
          appBar: _NoteEditorAppBar(
            noteId: widget.noteId,
            chromeAsync: chromeAsync,
            isReadOnly: isReadOnly,
            sessionAsync: sessionAsync,
          ),
          body: chromeAsync.when(
            data: (chrome) {
              if (chrome == null) {
                return const Center(child: Text(NoteStrings.errorNotFound));
              }
              return sessionAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) =>
                    const AppErrorView(title: NoteStrings.editorErrorTitle),
                data: (session) => _NoteEditorWithSession(
                  noteId: widget.noteId,
                  blockId: widget.blockId,
                  chrome: chrome,
                  isReadOnly: isReadOnly,
                  attachmentDelivery: widget.attachmentDelivery,
                  attachmentUploader: ref.read(attachmentsRepositoryProvider),
                  session: session,
                  taskForMetadata: _taskForMetadata,
                  readSession: _readSession,
                ),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) =>
                const AppErrorView(title: NoteStrings.editorErrorTitle),
          ),
        ),
      ),
    );
  }
}

/// The note fields the editor chrome renders.
///
/// Watching the projection keeps the screen from rebuilding the editor when
/// unrelated note fields, like the document content, change.
typedef _NoteEditorChrome = ({
  String? sharedByEmail,
  bool isOwner,
  bool hideCompleted,
  bool collapseImages,
  bool shouldAutofocus,
  bool isReadOnly,
});

_NoteEditorChrome _chromeFor(NoteModel note) => (
  sharedByEmail: note.sharedByEmail,
  isOwner: note.isOwner,
  hideCompleted: note.hideCompleted,
  collapseImages: note.collapseImages,
  shouldAutofocus: note.shouldAutofocus,
  isReadOnly: note.isReadOnly,
);

class _NoteEditorAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const _NoteEditorAppBar({
    required this.noteId,
    required this.chromeAsync,
    required this.isReadOnly,
    required this.sessionAsync,
  });

  final String noteId;
  final AsyncValue<_NoteEditorChrome?> chromeAsync;
  final bool isReadOnly;
  final AsyncValue<NoteEditorSession> sessionAsync;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppBar(
      automaticallyImplyLeading: false,
      backgroundColor: Colors.transparent,
      elevation: 0,
      actionsPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
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
      title: chromeAsync.when(
        data: (chrome) => isReadOnly && chrome?.sharedByEmail != null
            ? Text('${NoteStrings.sharedByPrefix} ${chrome!.sharedByEmail}')
            : null,
        loading: () => null,
        error: (_, _) => const Text(NoteStrings.editorErrorTitle),
      ),
      actions: chromeAsync.when(
        data: (chrome) => chrome == null || isReadOnly
            ? const <Widget>[]
            : [
                _NoteEditorMenuButton(noteId: noteId, chrome: chrome),
                const SizedBox(width: AppSpacing.xs),
                _NoteEditorPreferenceStatus(noteId: noteId),
                const SizedBox(width: AppSpacing.xs),
                _NoteEditorKeyboardButton(sessionAsync: sessionAsync),
              ],
        loading: () => const <Widget>[],
        error: (_, _) => const <Widget>[],
      ),
    );
  }
}

class _NoteEditorMenuButton extends ConsumerWidget {
  const _NoteEditorMenuButton({required this.noteId, required this.chrome});

  final String noteId;
  final _NoteEditorChrome chrome;

  Future<void> _handleSelection(
    BuildContext context,
    WidgetRef ref,
    String value,
  ) async {
    final session = ref.read(noteEditorSessionProvider(noteId)).value;
    if (session == null || !session.captureLocalOperations) return;

    final note = ref
        .read(noteProvider(noteId))
        .when(
          data: (note) => note,
          loading: () => null,
          error: (_, _) => null,
        );
    if (note == null) return;

    final mutationController = ref.read(
      notePreferenceMutationControllerProvider(noteId).notifier,
    );
    switch (value) {
      case 'share':
        await showAppBottomSheet<void>(
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = [
      if (chrome.isOwner)
        (
          value: 'share',
          label: NoteStrings.shareLabel,
          symbol: 'square.and.arrow.up',
          icon: Icons.share_outlined,
        ),
      (
        value: 'hide_completed',
        label: chrome.hideCompleted
            ? NoteStrings.showCompleted
            : NoteStrings.hideCompleted,
        symbol: chrome.hideCompleted ? 'eye' : 'eye.slash',
        icon: chrome.hideCompleted
            ? Icons.visibility_outlined
            : Icons.visibility_off_outlined,
      ),
      if (chrome.isOwner)
        (
          value: 'collapse_images',
          label: chrome.collapseImages
              ? 'Expandir imagens'
              : 'Colapsar imagens',
          symbol: 'photo',
          icon: Icons.image_outlined,
        ),
    ];
    return AppPopupMenu<String>(
      icon: Icons.more_vert,
      onSelected: (value) => unawaited(_handleSelection(context, ref, value)),
      items: [
        for (final entry in entries)
          AppPopupMenuItem(
            label: entry.label,
            value: entry.value,
            appleSymbol: entry.symbol,
            materialIcon: entry.icon,
          ),
      ],
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
          return Tooltip(
            message: 'Remover foco',
            child: AppPlatformIconButton(
              icon: Icons.check,
              size: 44,
              onPressed: () {
                session.controller.focusNode.unfocus();
                unawaited(
                  SystemChannels.textInput.invokeMethod<void>(
                    'TextInput.hide',
                  ),
                );
              },
            ),
          );
        },
      ),
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}

class _NoteEditorWithSession extends StatefulWidget {
  const _NoteEditorWithSession({
    required this.noteId,
    required this.blockId,
    required this.chrome,
    required this.isReadOnly,
    required this.attachmentDelivery,
    required this.attachmentUploader,
    required this.session,
    required this.taskForMetadata,
    required this.readSession,
  });

  final String noteId;
  final String? blockId;
  final _NoteEditorChrome chrome;
  final bool isReadOnly;
  final AttachmentDelivery? attachmentDelivery;
  final AttachmentUploader attachmentUploader;
  final NoteEditorSession session;
  final TaskMetadataDraft? Function(String taskId) taskForMetadata;
  final AsyncValue<NoteEditorSession> Function() readSession;

  @override
  State<_NoteEditorWithSession> createState() => _NoteEditorWithSessionState();
}

class _NoteEditorWithSessionState extends State<_NoteEditorWithSession> {
  bool _targetMissing = false;

  @override
  void initState() {
    super.initState();
    _resolveBlockTarget();
  }

  @override
  void didUpdateWidget(covariant _NoteEditorWithSession oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.blockId != widget.blockId ||
        oldWidget.session != widget.session) {
      _targetMissing = false;
      _resolveBlockTarget();
    }
  }

  void _resolveBlockTarget() {
    final blockId = widget.blockId;
    if (blockId == null || blockId.isEmpty) return;

    final controller = widget.session.controller;
    final node = controller.document.getNodeById(blockId);
    if (node is! TaskNode) {
      _targetMissing = true;
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !identical(widget.session.controller, controller) ||
          widget.blockId != blockId) {
        return;
      }
      final currentNode = controller.document.getNodeById(blockId);
      if (currentNode is TaskNode) {
        controller.composer.setSelectionWithReason(
          DocumentSelection.collapsed(
            position: DocumentPosition(
              nodeId: blockId,
              nodePosition: const TextNodePosition(offset: 0),
            ),
          ),
        );
      }
    });
  }

  void _retryBlockTarget() {
    _targetMissing = false;
    _resolveBlockTarget();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final taskDelegate = _NoteEditorTaskDelegate(
      context: context,
      taskForMetadata: widget.taskForMetadata,
      readSession: widget.readSession,
      isReadOnly: widget.isReadOnly,
    );
    final editor = NoteEditor(
      noteId: widget.noteId,
      session: widget.session,
      requestInitialFocus: widget.chrome.shouldAutofocus,
      hideCompleted: widget.chrome.hideCompleted,
      collapseImages: widget.chrome.collapseImages,
      isReadOnly: widget.isReadOnly,
      attachmentDelivery: widget.attachmentDelivery,
      attachmentUploader: widget.attachmentUploader,
      delegate: taskDelegate.create(),
    );
    if (!_targetMissing) return editor;

    return Column(
      children: [
        AppBanner(
          key: ValueKey('missing-block:${widget.blockId}'),
          message: 'Esta tarefa não está disponível nesta nota.',
          icon: Icons.search_off,
          action: AppButton(
            text: 'Tentar novamente',
            variant: AppButtonVariant.text,
            width: 160,
            onPressed: _retryBlockTarget,
          ),
        ),
        Expanded(child: editor),
      ],
    );
  }
}

class _NoteEditorTaskDelegate {
  const _NoteEditorTaskDelegate({
    required this.context,
    required this.taskForMetadata,
    required this.readSession,
    required this.isReadOnly,
  });

  final BuildContext context;
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
    final updatedTask = await showTaskMetadataSheet(
      context: context,
      draft: task,
    );
    if (context.mounted) {
      await _saveTaskMetadata(taskId, updatedTask);
    }
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

  Future<void> _onTaskReopen(String taskId, DateTime? scheduledAt) async {
    final controller = readSession().value?.controller;
    controller?.reopenTaskInEditor(taskId, scheduledAt: scheduledAt);
  }
}
