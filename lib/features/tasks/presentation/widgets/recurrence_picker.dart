import 'package:flutter/material.dart';
import 'package:supanotes/shared/widgets/app_selection_tile.dart';
import '../../domain/task_recurrence.dart';

class RecurrencePicker extends StatelessWidget {
  const RecurrencePicker({
    super.key,
    required this.initialRecurrence,
    required this.onChanged,
  });

  final TaskRecurrence? initialRecurrence;
  final ValueChanged<TaskRecurrence?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: AppSelectionTile(
            label: 'Nenhuma',
            icon: Icons.do_not_disturb_on_outlined,
            isSelected: initialRecurrence == null,
            onTap: () => onChanged(null),
          ),
        ),
        for (final option in TaskRecurrence.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppSelectionTile(
              label: option.label,
              icon: option.icon,
              isSelected: option == initialRecurrence,
              onTap: () => onChanged(option),
            ),
          ),
      ],
    );
  }
}
