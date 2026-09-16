import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supanotes/core/auth/current_user.dart';
import 'package:supanotes/features/tasks/application/task_controller.dart';
import 'package:supanotes/features/tasks/domain/task.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';
import 'package:supanotes/features/tasks/domain/task_reminder_option.dart';
import 'package:supanotes/features/tasks/presentation/controllers/task_metadata_draft.dart';
import 'package:supanotes/features/tasks/presentation/widgets/task_form.dart';
import 'package:supanotes/features/tasks/presentation/widgets/task_metadata_sheet.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/widgets/app_bottom_sheet.dart';
import 'package:supanotes/shared/widgets/app_error_view.dart';
import 'package:supanotes/shared/widgets/app_tile.dart';
import 'package:supanotes/shared/widgets/confirm_dialog.dart';
import 'package:uuid/uuid.dart';

class TaskEditorScreen extends ConsumerStatefulWidget {
  const TaskEditorScreen({this.taskId, super.key});

  final String? taskId;

  @override
  ConsumerState<TaskEditorScreen> createState() => _TaskEditorScreenState();
}

class _TaskEditorScreenState extends ConsumerState<TaskEditorScreen> {
  late final TextEditingController _titleController;
  late final String _metadataKey;
  late TaskMetadataDraft _metadata;
  AsyncValue<void> _saveState = const AsyncData(null);
  String? _loadedTaskId;

  bool get _isNew => widget.taskId == null;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _metadataKey = widget.taskId ?? const Uuid().v4();
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
    if (_isNew) {
      return AdaptiveScaffold(
        appBar: const AdaptiveAppBar(useNativeToolbar: false),
        body: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(AppSpacing.md),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  TaskForm(
                    titleController: _titleController,
                    metadata: _metadata,
                    onMetadataTap: _openMetadata,
                    onSave: () => _save(null),
                    isSaving: _saveState.isLoading,
                    errorText: _saveState.hasError
                        ? _saveState.error.toString()
                        : null,
                  ),
                ]),
              ),
            ),
          ],
        ),
      );
    }

    final taskAsync = ref.watch(standaloneTaskProvider(widget.taskId!));
    return AdaptiveScaffold(
      appBar: const AdaptiveAppBar(useNativeToolbar: false),
      body: CustomScrollView(
        slivers: [
          taskAsync.when(
            loading: () => const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => SliverFillRemaining(
              hasScrollBody: false,
              child: AppErrorView(
                title: 'Erro ao carregar a task',
                subtitle: error.toString(),
                onRetry: () => ref.invalidate(
                  standaloneTaskProvider(widget.taskId!),
                ),
              ),
            ),
            data: (task) {
              if (task == null) {
                return const SliverFillRemaining(
                  hasScrollBody: false,
                  child: AppErrorView(title: 'Task não encontrada'),
                );
              }
              _synchronizeTask(task);
              return SliverPadding(
                padding: const EdgeInsets.all(AppSpacing.md),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    TaskForm(
                      titleController: _titleController,
                      metadata: _metadata,
                      onMetadataTap: _openMetadata,
                      onSave: () => _save(task),
                      onDelete: () => _delete(task),
                      isSaving: _saveState.isLoading,
                      errorText: _saveState.hasError
                          ? _saveState.error.toString()
                          : null,
                    ),
                  ]),
                ),
              );
            },
          ),
        ],
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
      completions: {
        for (final entry in task.completions.entries)
          if (DateTime.tryParse(entry.key) != null &&
              DateTime.tryParse(entry.value) != null)
            DateTime.parse(entry.key): DateTime.parse(entry.value),
      },
    );
  }

  Future<void> _openMetadata() async {
    await showAppBottomSheet<void>(
      context: context,
      builder: (sheetContext) => ListView(
        children: [
          const Text(
            'Detalhes da task',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppSpacing.md),
          AppTile(
            title: 'Data, horário e recorrência',
            subtitle: 'Escolha quando esta task deve aparecer',
            leading: const Icon(Icons.event_note_outlined),
            onTap: () async {
              Navigator.of(sheetContext).pop();
              await showTaskMetadataSheet(
                context: context,
                ref: ref,
                taskId: _metadataKey,
                draft: _metadata,
                onSave: (draft) async {
                  if (mounted) setState(() => _metadata = draft);
                },
              );
            },
          ),
        ],
      ),
    );
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
      final controller = ref.read(taskControllerProvider);
      if (task == null) {
        final ownerUserId = ref.read(currentUserIdProvider);
        if (ownerUserId == null || ownerUserId.isEmpty) {
          throw StateError('É necessário estar autenticado para criar tasks');
        }
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
    } catch (error, stackTrace) {
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
    } catch (error, stackTrace) {
      if (mounted) setState(() => _saveState = AsyncError(error, stackTrace));
    }
  }
}
