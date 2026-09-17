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
import 'package:supanotes/shared/widgets/app_error_view.dart';
import 'package:supanotes/shared/widgets/confirm_dialog.dart';
import 'package:supanotes/shared/widgets/global_sheet.dart';
import 'package:uuid/uuid.dart';

/// Opens the standalone task editor directly in the app's global sheet.
Future<void> showTaskEditorSheet({
  required BuildContext context,
  String? taskId,
  Task? task,
}) async {
  await showGlobalSheet<void>(
    context: context,
    builder: (_) => TaskEditorScreen(taskId: taskId, task: task),
  );
}

class TaskEditorScreen extends ConsumerStatefulWidget {
  const TaskEditorScreen({this.taskId, this.task, super.key})
    : assert(taskId == null || task == null);

  final String? taskId;
  final Task? task;

  @override
  ConsumerState<TaskEditorScreen> createState() => _TaskEditorScreenState();
}

class _TaskEditorScreenState extends ConsumerState<TaskEditorScreen> {
  late final TextEditingController _titleController;
  late final String _metadataKey;
  late TaskMetadataDraft _metadata;
  AsyncValue<void> _saveState = const AsyncData(null);
  String? _loadedTaskId;

  bool get _isNew => widget.taskId == null && widget.task == null;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _metadataKey = widget.task?.id ?? widget.taskId ?? const Uuid().v4();
    _metadata = const TaskMetadataDraft(
      scheduleAnchor: null,
      hasTime: false,
      recurrence: null,
      reminder: null,
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
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
      return GlobalSheetPage(
        title: 'Criar/Editar nota',
        child: TaskEditorForm(
          titleController: _titleController,
          metadata: _metadata,
          onMetadataChanged: _onMetadataChanged,
          onCancel: context.pop,
          onSave: () => _save(widget.task),
          onDelete: () => _delete(widget.task!),
          isSaving: saveView.isSaving,
          errorText: saveView.errorText,
        ),
      );
    }

    if (_isNew) {
      return GlobalSheetPage(
        title: 'Criar/Editar nota',
        child: TaskEditorForm(
          titleController: _titleController,
          metadata: _metadata,
          onMetadataChanged: _onMetadataChanged,
          onCancel: context.pop,
          onSave: () => _save(null),
          isSaving: saveView.isSaving,
          errorText: saveView.errorText,
        ),
      );
    }

    final taskId = widget.taskId!;
    final taskAsync = ref.watch(standaloneTaskProvider(taskId));
    return GlobalSheetPage(
      title: 'Criar/Editar nota',
      child: taskAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => AppErrorView(
          title: 'Erro ao carregar a task',
          subtitle: error.toString(),
          onRetry: () => ref.invalidate(standaloneTaskProvider(taskId)),
        ),
        data: (task) {
          if (task == null) {
            return const AppErrorView(title: 'Task não encontrada');
          }
          _synchronizeTask(task);
          return TaskEditorForm(
            titleController: _titleController,
            metadata: _metadata,
            onMetadataChanged: _onMetadataChanged,
            onCancel: context.pop,
            onSave: () => _save(task),
            onDelete: () => _delete(task),
            isSaving: saveView.isSaving,
            errorText: saveView.errorText,
          );
        },
      ),
    );
  }

  void _synchronizeTask(Task task) {
    if (_loadedTaskId == task.id) return;
    _loadedTaskId = task.id;
    _titleController.text = task.title;
    _metadata = TaskMetadataDraft(
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

  void _onMetadataChanged(TaskMetadataDraft draft) {
    setState(() => _metadata = draft);
    if (draft.reminder != null) {
      unawaited(
        ref
            .read(taskNotificationSchedulerProvider.notifier)
            .requestPermissionForReminder(),
      );
    }
  }

  Future<void> _save(Task? task) async {
    final title = _titleController.text.trim();
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
      final draft = _metadata;
      if (task == null) {
        final ownerUserId = ref.read(currentUserIdProvider);
        if (ownerUserId == null || ownerUserId.isEmpty) {
          throw StateError('É necessário estar autenticado para criar tasks');
        }
        final controller = ref.read(taskControllerProvider);
        final now = DateTime.now().toUtc();
        await controller.create(
          Task(
            id: _metadataKey,
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
    final confirmed = await showConfirmDialog(
      context: context,
      title: 'Excluir task?',
      message: 'Essa task será removida da sua lista.',
      confirmLabel: 'Excluir',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _saveState = const AsyncLoading());
    try {
      await ref.read(taskControllerProvider).delete(task.id);
      if (mounted) context.pop();
    } on Object catch (error, stackTrace) {
      if (mounted) setState(() => _saveState = AsyncError(error, stackTrace));
    }
  }
}
