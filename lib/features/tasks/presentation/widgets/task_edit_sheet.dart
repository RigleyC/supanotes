import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/widgets/app_bottom_sheet.dart';
import 'package:supanotes/shared/widgets/app_button.dart';
import 'package:supanotes/shared/widgets/app_input.dart';
import 'package:supanotes/shared/widgets/app_snackbar.dart';

import '../../data/tasks_repository.dart';
import '../../domain/task_model.dart';
import 'due_date_picker.dart';
import 'recurrence_picker.dart';

/// Bottom-sheet form for creating or editing a task.
///
/// Pass `task: null` to create, or an existing [TaskModel] to edit.
/// Pops the (possibly-updated) [TaskModel] back through `Navigator.pop`
/// when the user taps **Salvar**. **Excluir** is only shown for
/// existing tasks and pops `null` to signal a delete.
class TaskEditSheet extends ConsumerStatefulWidget {
  const TaskEditSheet({
    super.key,
    required this.noteId,
    this.task,
  });

  final String noteId;
  final TaskModel? task;

  static Future<TaskEditResult?> show(
    BuildContext context, {
    required String noteId,
    TaskModel? task,
  }) {
    return showAppBottomSheet<TaskEditResult>(
      context: context,
      builder: (_) => TaskEditSheet(noteId: noteId, task: task),
    );
  }

  @override
  ConsumerState<TaskEditSheet> createState() => _TaskEditSheetState();
}

class _TaskEditSheetState extends ConsumerState<TaskEditSheet> {
  late final TextEditingController _titleController;
  late DateTime? _dueDate;
  late String? _recurrence;
  bool _saving = false;

  bool get _isEdit => widget.task != null;

  @override
  void initState() {
    super.initState();
    final t = widget.task;
    _titleController = TextEditingController(text: t?.title ?? '');
    _dueDate = t?.dueDate;
    _recurrence = t?.recurrence;
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _onSave() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      AppMessenger.showInfo(context, 'Digite um título para a tarefa.');
      return;
    }

    setState(() => _saving = true);
    final repo = ref.read(tasksRepositoryProvider);
    final navigator = Navigator.of(context);

    try {
      if (_isEdit) {
        final original = widget.task!;
        await repo.updateTask(
          original.id,
          title: title,
          dueDate: _dueDate,
          recurrence: _recurrence,
          clearDueDate: _dueDate == null,
          clearRecurrence: (_recurrence == null || _recurrence!.isEmpty),
        );
        navigator.pop(
          TaskEditResult(
            task: TaskModel(
              id: original.id,
              userId: original.userId,
              noteId: original.noteId,
              title: title,
              status: original.status,
              position: original.position,
              dueDate: _dueDate,
              completedAt: original.completedAt,
              recurrence: _recurrence,
              createdAt: original.createdAt,
              updatedAt: DateTime.now().toUtc(),
            ),
            deleted: false,
          ),
        );
      } else {
        final created = await repo.createTask(
          noteId: widget.noteId,
          title: title,
          dueDate: _dueDate,
          recurrence: _recurrence,
        );
        navigator.pop(TaskEditResult(task: created, deleted: false));
      }
    } catch (e) {
      AppMessenger.showError(context, 'Erro ao salvar tarefa: $e');
      setState(() => _saving = false);
    }
  }

  Future<void> _onDelete() async {
    final task = widget.task;
    if (task == null) return;
    setState(() => _saving = true);
    final repo = ref.read(tasksRepositoryProvider);
    final navigator = Navigator.of(context);
    try {
      await repo.deleteTask(task.id);
      navigator.pop(TaskEditResult(task: task, deleted: true));
    } catch (e) {
      AppMessenger.showError(context, 'Erro ao excluir tarefa: $e');
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
            _isEdit ? 'Editar tarefa' : 'Nova tarefa',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.lg),
          AppInput(
            controller: _titleController,
            autofocus: !_isEdit,
            textInputAction: TextInputAction.done,
            maxLines: 3,
            labelText: 'Título',
            hintText: 'O que precisa ser feito?',
            onSubmitted: (_) => _onSave(),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Data de vencimento', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          DueDatePicker(
            initialDate: _dueDate,
            onChanged: (d) => setState(() => _dueDate = d),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Repetição', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          RecurrencePicker(
            initialRecurrence: _recurrence,
            onChanged: (r) => setState(() => _recurrence = r),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              if (_isEdit)
                IntrinsicWidth(
                  child: AppButton(
                    text: 'Excluir',
                    onPressed: _saving ? null : _onDelete,
                    variant: AppButtonVariant.danger,
                    isLoading: _saving,
                  ),
                ),
              const Spacer(),
              IntrinsicWidth(
                child: AppButton(
                  text: 'Cancelar',
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  variant: AppButtonVariant.secondary,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              IntrinsicWidth(
                child: AppButton(
                  text: 'Salvar',
                  onPressed: _saving ? null : _onSave,
                  isLoading: _saving,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Result returned from [TaskEditSheet.show] via `Navigator.pop`.
class TaskEditResult {
  const TaskEditResult({required this.task, required this.deleted});
  final TaskModel? task;
  final bool deleted;
}
