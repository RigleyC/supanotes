import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supanotes/core/auth/current_user.dart';
import 'package:supanotes/features/tasks/application/task_controller.dart';
import 'package:supanotes/features/tasks/domain/task.dart';
import 'package:supanotes/features/tasks/domain/task_notification_scheduler.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';
import 'package:supanotes/features/tasks/domain/task_reminder_option.dart';
import 'package:supanotes/features/tasks/domain/task_schedule_identity.dart';
import 'package:supanotes/features/tasks/presentation/controllers/task_metadata_draft.dart';
import 'package:supanotes/features/tasks/presentation/widgets/task_editor_form.dart';
import 'package:supanotes/features/tasks/presentation/widgets/task_editor_sheet.dart';
import 'package:supanotes/shared/widgets/app_error_view.dart';
import 'package:supanotes/shared/widgets/global_sheet.dart';
import 'package:uuid/uuid.dart';

/// Session-owned editing state for one task-editor sheet invocation.
///
/// Instances live in the [showTaskEditorSheet] closure — outside the sheet's
/// page subtree. Pushing a picker page unmounts the whole sheet content (and
/// the transition briefly mounts duplicates), so state owned by the screen
/// would be discarded and its [ValueNotifier] disposed while a selection is
/// still pending. Mounts [retain]/[release]; the last release disposes. This
/// keeps title, draft and in-flight selections alive across push/pop cycles,
/// and guarantees disposal only after the sheet is truly gone: the sheet
/// future completes before its exit animation ends, so disposing there races
/// rebuilds of the still-mounted subtree.
final class _TaskEditorSession {
  _TaskEditorSession({Task? task, String? newTaskId})
    : titleController = TextEditingController(text: task?.title ?? ''),
      draftNotifier = ValueNotifier<TaskMetadataDraft>(_draftForTask(task)),
      newTaskId = task?.id ?? newTaskId ?? const Uuid().v4() {
    titleController.addListener(_onTitleChanged);
  }

  final TextEditingController titleController;
  final ValueNotifier<TaskMetadataDraft> draftNotifier;

  /// Stable id for a created task, so a remount between concurrent saves
  /// cannot mint a second task.
  final String newTaskId;

  /// Last task snapshot applied to the controllers. Lives here (not in the
  /// screen State) so a picker push/pop remount never re-applies a stale
  /// snapshot over in-flight edits.
  Task? lastSyncedTask;

  /// Local-first guards: once the user has typed in the title or edited the
  /// metadata draft, a later remote snapshot must never be re-applied over
  /// their in-flight input. Reassigning `TextEditingController.text` mid-typing
  /// resets the cursor and corrupts the IME composition, interleaving the
  /// letters that follow.
  bool titleTouched = false;
  bool draftTouched = false;

  /// True while [applyTask] is assigning, so its own change notifications are
  /// not mistaken for user edits (and never fire the permission prompt).
  bool applyingTask = false;

  int _retains = 0;

  void retain() => _retains++;

  void release() {
    assert(_retains > 0, 'Task editor session released without a retain');
    if (--_retains > 0) return;
    titleController.removeListener(_onTitleChanged);
    titleController.dispose();
    draftNotifier.dispose();
  }

  void _onTitleChanged() {
    if (applyingTask) return;
    titleTouched = true;
  }

  /// Applies a task snapshot to the controllers. Must never run during
  /// `build`: sibling subtrees (sheet height measurer, crossfade duplicates)
  /// listen to the same objects, and notifying them mid-build crashes.
  void applyTask(Task task) {
    lastSyncedTask = task;
    applyingTask = true;
    try {
      // Skip identical text: assigning `.text` also resets the selection,
      // which would move the cursor even when the content is unchanged.
      if (titleController.text != task.title) {
        titleController.text = task.title;
      }
      draftNotifier.value = _draftForTask(task);
    } finally {
      applyingTask = false;
    }
  }
}

/// Opens the standalone task editor directly in the app's global sheet.
Future<void> showTaskEditorSheet({
  required BuildContext context,
  String? taskId,
  Task? task,
}) async {
  final session = _TaskEditorSession(task: task);
  session.retain();
  try {
    await showGlobalSheet<void>(
      context: context,
      builder: (_) =>
          TaskEditorScreen(taskId: taskId, task: task, session: session),
    );
  } finally {
    session.release();
  }
}

/// Initial metadata draft for a task, shared by the sheet opener (which seeds
/// externally-owned controllers) and the screen fallback (async task load).
TaskMetadataDraft _draftForTask(Task? task) {
  if (task == null) {
    return const TaskMetadataDraft(
      scheduleAnchor: null,
      hasTime: false,
      recurrence: null,
      reminder: null,
    );
  }
  return TaskMetadataDraft(
    scheduleAnchor: task.dueDate,
    hasTime: task.hasTime,
    recurrence: TaskRecurrence.parse(task.recurrenceRule),
    reminder: TaskReminderOption.fromValue(task.reminder),
    completions: readScheduledCompletions(
      task.completions,
      hasTime: task.hasTime,
    ),
  );
}

class TaskEditorScreen extends ConsumerStatefulWidget {
  const TaskEditorScreen({
    this.taskId,
    this.task,
    this.session,
    super.key,
  }) : assert(taskId == null || task == null);

  final String? taskId;
  final Task? task;

  /// Externally-owned editing state, provided by [showTaskEditorSheet].
  /// When present, the screen retains/releases it instead of owning it, so
  /// title and draft survive the sheet's page push/pop cycles (which unmount
  /// this subtree, sometimes with transient duplicate mounts).
  final _TaskEditorSession? session;

  @override
  ConsumerState<TaskEditorScreen> createState() => _TaskEditorScreenState();
}

class _TaskEditorScreenState extends ConsumerState<TaskEditorScreen> {
  late final _TaskEditorSession _session;
  late final FocusNode _titleFocusNode;
  AsyncValue<void> _saveState = const AsyncData(null);
  Task? _syncPending;
  TaskMetadataDraft? _lastDraft;
  bool _focusRequested = false;

  bool get _isNew => widget.taskId == null && widget.task == null;

  @override
  void initState() {
    super.initState();
    _session = widget.session ?? _TaskEditorSession(task: widget.task);
    _session.retain();
    _lastDraft = _session.draftNotifier.value;
    _session.draftNotifier.addListener(_onDraftChanged);
    _titleFocusNode = FocusNode();
    // `autofocus` on the field fires before the bottom-sheet route settles,
    // which opens the keyboard without delivering focus to the input.
    // Requesting focus after the first frame lands it reliably, and re-runs
    // after a picker push/pop remounts this subtree.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _focusRequested) return;
      _focusRequested = true;
      _titleFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _session.draftNotifier.removeListener(_onDraftChanged);
    _session.release();
    _titleFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final saveView = _saveState.when(
      data: (_) => (isSaving: false, errorText: null),
      loading: () => (isSaving: true, errorText: null),
      error: (error, _) => (isSaving: false, errorText: error.toString()),
    );

    if (widget.task != null) {
      _synchronizeTask(widget.task!);
      return TaskEditorSheet(
        onCancel: context.pop,
        onSave: () => _save(widget.task),
        onDelete: () => _delete(widget.task!),
        isSaving: saveView.isSaving,
        child: TaskEditorForm(
          titleController: _session.titleController,
          titleFocusNode: _titleFocusNode,
          draftNotifier: _session.draftNotifier,
          onSubmitted: () => unawaited(_save(widget.task)),
          errorText: saveView.errorText,
        ),
      );
    }

    if (_isNew) {
      return TaskEditorSheet(
        onCancel: context.pop,
        onSave: () => _save(null),
        isSaving: saveView.isSaving,
        child: TaskEditorForm(
          titleController: _session.titleController,
          titleFocusNode: _titleFocusNode,
          draftNotifier: _session.draftNotifier,
          onSubmitted: () => unawaited(_save(null)),
          errorText: saveView.errorText,
        ),
      );
    }

    final taskId = widget.taskId!;
    final taskAsync = ref.watch(standaloneTaskProvider(taskId));
    return taskAsync.when(
      loading: () => TaskEditorSheet(
        onCancel: context.pop,
        onSave: () async {},
        isSaving: true,
        child: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => TaskEditorSheet(
        onCancel: context.pop,
        onSave: () async {},
        child: AppErrorView(
          title: 'Erro ao carregar a task',
          subtitle: error.toString(),
          onRetry: () => ref.invalidate(standaloneTaskProvider(taskId)),
        ),
      ),
      data: (task) {
        if (task == null) {
          return TaskEditorSheet(
            onCancel: context.pop,
            onSave: () async {},
            child: const AppErrorView(title: 'Task não encontrada'),
          );
        }
        _synchronizeTask(task);
        return TaskEditorSheet(
          onCancel: context.pop,
          onSave: () => _save(task),
          onDelete: () => _delete(task),
          isSaving: saveView.isSaving,
          child: TaskEditorForm(
            titleController: _session.titleController,
            titleFocusNode: _titleFocusNode,
            draftNotifier: _session.draftNotifier,
            onSubmitted: () => unawaited(_save(task)),
            errorText: saveView.errorText,
          ),
        );
      },
    );
  }

  void _synchronizeTask(Task task) {
    // Value equality: re-seeds on genuine remote changes, but never clobbers
    // in-flight title/metadata edits after a picker push/pop remount (which
    // replays the same snapshot through a fresh State).
    if (task == _session.lastSyncedTask || task == _syncPending) return;
    if (_session.lastSyncedTask == null) {
      // Virgin session: no sibling subtree can be listening yet, so seeding
      // synchronously keeps the first painted frame correct.
      _session.applyTask(task);
      _lastDraft = _session.draftNotifier.value;
      return;
    }
    if (_session.titleTouched || _session.draftTouched) {
      // Local-first: the user already edited this task in the sheet. Record
      // the snapshot as seen (so equal re-emissions short-circuit) but never
      // write it back over their unsaved input.
      _session.lastSyncedTask = task;
      return;
    }
    _syncPending = task;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncPending = null;
      if (!mounted) return;
      _session.applyTask(task);
      _lastDraft = _session.draftNotifier.value;
    });
  }

  void _onDraftChanged() {
    final next = _session.draftNotifier.value;
    // A programmatic re-seed (applyTask) is not a user action: it must not
    // mark the draft as touched nor fire the permission prompt.
    if (!_session.applyingTask) _session.draftTouched = true;
    // The platform permission prompt is expensive: only fire it when a
    // reminder is newly added, not on every tweak while one is already set.
    // The service itself skips the prompt when already granted.
    final hadReminder = _lastDraft?.reminder != null;
    _lastDraft = next;
    if (_session.applyingTask) return;
    if (next.reminder != null && !hadReminder) {
      unawaited(
        ref
            .read(taskNotificationSchedulerProvider.notifier)
            .requestPermissionForReminder(),
      );
    }
  }

  Future<void> _save(Task? task) async {
    final title = _session.titleController.text.trim();
    if (title.isEmpty) {
      setState(() {
        _saveState = AsyncError(
          const FormatException('Digite um título para a task.'),
          StackTrace.current,
        );
      });
      return;
    }
    setState(() => _saveState = const AsyncLoading());
    try {
      final draft = _session.draftNotifier.value;
      if (task == null) {
        final ownerUserId = ref.read(currentUserIdProvider);
        if (ownerUserId == null || ownerUserId.isEmpty) {
          throw StateError('É necessário estar autenticado para criar tasks');
        }
        final controller = ref.read(taskControllerProvider);
        final now = DateTime.now().toUtc();
        await controller.create(
          Task(
            id: _session.newTaskId,
            ownerUserId: ownerUserId,
            title: title,
            dueDate: draft.scheduleAnchor,
            hasTime: draft.hasTime,
            recurrenceRule: draft.recurrence?.name,
            reminder: draft.reminder?.value,
            createdAt: now,
            updatedAt: now,
          ),
        );
      } else {
        final controller = ref.read(taskControllerProvider);
        final scheduled = task.withSchedule(
          dueDate: draft.scheduleAnchor,
          hasTime: draft.hasTime,
          recurrenceRule: draft.recurrence?.name,
        );
        await controller.update(
          scheduled.copyWith(
            title: title,
            reminder: draft.reminder?.value,
          ),
        );
      }
      if (mounted) context.pop();
    } on Object catch (error, stackTrace) {
      if (mounted) {
        setState(() => _saveState = AsyncError(error, stackTrace));
      }
    }
  }

  Future<void> _delete(Task task) async {
    setState(() => _saveState = const AsyncLoading());
    try {
      await ref.read(taskControllerProvider).delete(task.id);
      if (mounted) context.pop();
    } on Object catch (error, stackTrace) {
      if (mounted) setState(() => _saveState = AsyncError(error, stackTrace));
    }
  }
}
