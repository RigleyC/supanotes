import 'package:flutter/material.dart';
import 'package:supanotes/shared/widgets/app_selection_tile.dart';
import '../../domain/task_recurrence.dart';

class RecurrencePicker extends StatelessWidget {
  const RecurrencePicker({
    super.key,
    required this.initialRecurrence,
    required this.onChanged,
    this.dueDate,
  });

  final TaskRecurrence? initialRecurrence;
  final ValueChanged<TaskRecurrence?> onChanged;
  final DateTime? dueDate;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSelectionTile(
          label: 'Nenhuma',
          icon: Icons.do_not_disturb_on_outlined,
          isSelected: initialRecurrence == null,
          onTap: () => onChanged(null),
        ),
        for (final option in TaskRecurrence.values)
          AppSelectionTile(
            label: option.getLocalizedLabel(dueDate),
            icon: option.icon,
            isSelected: option == initialRecurrence,
            onTap: () => onChanged(option),
          ),
      ],
    );
  }
}
