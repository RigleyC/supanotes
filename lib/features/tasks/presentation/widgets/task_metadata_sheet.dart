import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supanotes/features/notes/presentation/controllers/note_editor_provider.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/widgets/app_button.dart';

import '../../domain/task_model.dart';
import '../../domain/task_recurrence.dart';
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

  @override
  ConsumerState<TaskMetadataSheet> createState() => _TaskMetadataSheetState();
}

class _TaskMetadataSheetState extends ConsumerState<TaskMetadataSheet> {
  late DateTime? _dueDate;
  late TaskRecurrence? _recurrence;
  late bool _hasTime;

  @override
  void initState() {
    super.initState();
    final t = widget.task;
    _dueDate = t.dueDate;
    _recurrence = t.recurrence;
    _hasTime = t.hasTime;
  }

  void _onSave() {
    final noteId = widget.noteId;
    final taskId = widget.task.id;

    ref
        .read(noteEditorControllerProvider(noteId))
        .updateTaskMetadataInYDoc(
          taskId,
          dueDate: _dueDate,
          clearDueDate: _dueDate == null,
          recurrence: _recurrence?.name,
          clearRecurrence: _recurrence == null,
          hasTime: _hasTime,
        );

    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: AppSpacing.sm,
        children: [
          Text(
            'Data de vencimento',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          DueDatePicker(
            initialDate: _dueDate,
            initialHasTime: _hasTime,
            onChanged: (d, {bool hasTime = false}) => setState(() {
              _dueDate = d;
              _hasTime = hasTime;
              if (d == null) _recurrence = null;
            }),
          ),
          Text('Repetição', style: Theme.of(context).textTheme.titleMedium),
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
          AppButton(text: 'Salvar', onPressed: _onSave),
        ],
      ),
    );
  }
}
