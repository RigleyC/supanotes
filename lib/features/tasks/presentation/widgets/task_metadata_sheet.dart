import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/widgets/app_bottom_sheet.dart';
import 'package:supanotes/shared/widgets/app_button.dart';
import 'package:supanotes/shared/widgets/app_snackbar.dart';

import '../../domain/task_model.dart';
import '../../domain/task_recurrence.dart';
import '../controllers/task_controller.dart';
import 'due_date_picker.dart';
import 'recurrence_picker.dart';
import 'package:supanotes/core/utils/date_time_extensions.dart';

/// Bottom-sheet for editing a task's metadata (date and recurrence).
///
/// Must be called with an existing [TaskModel].
/// Pops when the user taps **Salvar**.
class TaskMetadataSheet extends ConsumerStatefulWidget {
  const TaskMetadataSheet({
    super.key,
    required this.noteId,
    required this.task,
  });

  final String noteId;
  final TaskModel task;

  static Future<void> show(
    BuildContext context, {
    required String noteId,
    required TaskModel task,
  }) {
    return showAppBottomSheet(
      context: context,
      builder: (_) => TaskMetadataSheet(noteId: noteId, task: task),
    );
  }

  @override
  ConsumerState<TaskMetadataSheet> createState() => _TaskMetadataSheetState();
}

class _TaskMetadataSheetState extends ConsumerState<TaskMetadataSheet> {
  late DateTime? _dueDate;
  late TaskRecurrence? _recurrence;

  @override
  void initState() {
    super.initState();
    final t = widget.task;
    _dueDate = t.dueDate;
    _recurrence = t.recurrence;
  }

  Future<void> _onSave() async {
    final controller = ref.read(taskControllerProvider.notifier);

    await controller.updateTaskMetadata(
      taskId: widget.task.id,
      title: widget.task.title,
      dueDate: _dueDate,
      recurrence: _recurrence,
      clearDueDate: _dueDate == null,
      clearRecurrence: _recurrence == null,
    );

    if (ref.read(taskControllerProvider).hasError) {
      if (mounted) AppMessenger.showError('Erro ao salvar tarefa');
      return;
    }

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Data de vencimento',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          DueDatePicker(
            initialDate: _dueDate,
            onChanged: (d) => setState(() {
              _dueDate = d;
              if (d == null) _recurrence = null;
            }),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Repetição', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.md),
          RecurrencePicker(
            initialRecurrence: _recurrence,
            dueDate: _dueDate,
            onChanged: (r) => setState(() {
              _recurrence = r;
              if (r != null && _dueDate == null) {
                _dueDate = DateTime.now().startOfDay;
              }
            }),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  text: 'Cancelar',
                  onPressed: ref.watch(taskControllerProvider).isLoading
                      ? null
                      : () => Navigator.of(context).pop(),
                  variant: AppButtonVariant.secondary,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: AppButton(
                  text: 'Salvar',
                  onPressed: ref.watch(taskControllerProvider).isLoading
                      ? null
                      : _onSave,
                  isLoading: ref.watch(taskControllerProvider).isLoading,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
