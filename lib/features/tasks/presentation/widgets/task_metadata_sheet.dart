import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/widgets/app_bottom_sheet.dart';
import 'package:supanotes/shared/widgets/app_button.dart';
import 'package:supanotes/shared/widgets/app_snackbar.dart';

import '../../data/tasks_repository.dart';
import '../../domain/task_model.dart';
import '../../domain/task_recurrence.dart';
import 'due_date_picker.dart';
import 'recurrence_picker.dart';
import 'package:supanotes/core/utils/date_time_extensions.dart';

/// Bottom-sheet for editing a task's metadata (date and recurrence).
///
/// Must be called with an existing [TaskModel].
/// Pops the (possibly-updated) [TaskModel] back through `Navigator.pop`
/// when the user taps **Salvar**.
class TaskMetadataSheet extends ConsumerStatefulWidget {
  const TaskMetadataSheet({
    super.key,
    required this.noteId,
    required this.task,
  });

  final String noteId;
  final TaskModel task;

  static Future<TaskModel?> show(
    BuildContext context, {
    required String noteId,
    required TaskModel task,
  }) {
    return showAppBottomSheet<TaskModel>(
      context: context,
      builder: (_) => TaskMetadataSheet(
        noteId: noteId,
        task: task,
      ),
    );
  }

  @override
  ConsumerState<TaskMetadataSheet> createState() => _TaskMetadataSheetState();
}

class _TaskMetadataSheetState extends ConsumerState<TaskMetadataSheet> {
  late DateTime? _dueDate;
  late TaskRecurrence? _recurrence;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final t = widget.task;
    _dueDate = t.dueDate;
    _recurrence = t.recurrence;
  }

  Future<void> _onSave() async {
    setState(() => _saving = true);
    final repo = ref.read(tasksRepositoryProvider);
    final navigator = Navigator.of(context);

    try {
      final original = widget.task;
      await repo.updateTask(
        original.id,
        title: original.title,
        dueDate: _dueDate,
        recurrence: _recurrence,
        clearDueDate: _dueDate == null,
        clearRecurrence: _recurrence == null,
      );
      navigator.pop(
        TaskModel(
          id: original.id,
          userId: original.userId,
          noteId: original.noteId,
          title: original.title,
          status: original.status,
          position: original.position,
          dueDate: _dueDate,
          completedAt: original.completedAt,
          recurrence: _recurrence,
          createdAt: original.createdAt,
          updatedAt: DateTime.now().toUtc(),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      AppMessenger.showError('Erro ao salvar tarefa: $e');
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
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  variant: AppButtonVariant.secondary,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
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
