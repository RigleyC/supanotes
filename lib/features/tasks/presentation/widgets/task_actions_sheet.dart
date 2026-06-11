import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/features/tasks/data/tasks_repository.dart';
import 'package:supanotes/features/tasks/domain/task_model.dart';
import 'package:supanotes/features/tasks/presentation/widgets/due_date_picker.dart';
import 'package:supanotes/features/tasks/presentation/widgets/recurrence_picker.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/widgets/app_bottom_sheet.dart';
import 'package:supanotes/shared/widgets/app_button.dart';
import 'package:supanotes/shared/widgets/app_snackbar.dart';

class TaskActionsSheet extends ConsumerStatefulWidget {
  const TaskActionsSheet({super.key, required this.task});

  final TaskModel task;

  static Future<void> show(BuildContext context, {required TaskModel task}) {
    return showAppBottomSheet<void>(
      context: context,
      builder: (_) => TaskActionsSheet(task: task),
    );
  }

  @override
  ConsumerState<TaskActionsSheet> createState() => _TaskActionsSheetState();
}

class _TaskActionsSheetState extends ConsumerState<TaskActionsSheet> {
  late DateTime? _dueDate;
  late String? _recurrence;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _dueDate = widget.task.dueDate;
    _recurrence = widget.task.recurrence;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    try {
      await ref
          .read(tasksRepositoryProvider)
          .updateTask(
            widget.task.id,
            dueDate: _dueDate,
            recurrence: _recurrence,
            clearDueDate: _dueDate == null,
            clearRecurrence: _recurrence == null || _recurrence!.isEmpty,
          );
      navigator.pop();
    } catch (e) {
      if (!mounted) return;
      AppMessenger.showError(context, 'Erro ao salvar tarefa: $e');
      setState(() => _saving = false);
    }
  }

  Future<void> _toggleComplete() async {
    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    try {
      final repo = ref.read(tasksRepositoryProvider);
      if (widget.task.isCompleted) {
        await repo.reopenTask(widget.task.id);
      } else {
        await repo.completeTask(widget.task.id);
      }
      navigator.pop();
    } catch (e) {
      if (!mounted) return;
      AppMessenger.showError(context, 'Erro ao atualizar tarefa: $e');
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Op\u00e7\u00f5es da tarefa',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            widget.task.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Data de vencimento',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          DueDatePicker(
            initialDate: _dueDate,
            onChanged: (date) => setState(() => _dueDate = date),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Repeti\u00e7\u00e3o',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          RecurrencePicker(
            initialRecurrence: _recurrence,
            onChanged: (value) => setState(() => _recurrence = value),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              IntrinsicWidth(
                child: AppButton(
                  text: widget.task.isCompleted ? 'Reabrir' : 'Concluir',
                  variant: AppButtonVariant.secondary,
                  onPressed: _saving ? null : _toggleComplete,
                ),
              ),
              const Spacer(),
              IntrinsicWidth(
                child: AppButton(
                  text: 'Cancelar',
                  variant: AppButtonVariant.secondary,
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              IntrinsicWidth(
                child: AppButton(
                  text: 'Salvar',
                  isLoading: _saving,
                  onPressed: _saving ? null : _save,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
