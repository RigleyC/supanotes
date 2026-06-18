import 'package:flutter/material.dart';
import 'package:supanotes/shared/widgets/app_choice_chip.dart';

import '../../domain/task_recurrence.dart';

/// Chip-based picker for the `recurrence` column.
///
/// Renders five options ("Nenhuma", "Diária", "Dias úteis", "Semanal",
/// "Mensal") and emits the corresponding enum value. The
/// selected chip is highlighted with the theme primary color and a
/// check icon.
class RecurrencePicker extends StatelessWidget {
  const RecurrencePicker({
    super.key,
    required this.initialRecurrence,
    required this.onChanged,
  });

  final TaskRecurrence? initialRecurrence;
  final ValueChanged<TaskRecurrence?> onChanged;

  static const _options = <_RecurrenceOption>[
    _RecurrenceOption(value: null, label: 'Nenhuma', icon: Icons.do_not_disturb_on_outlined),
    _RecurrenceOption(value: TaskRecurrence.daily, label: 'Diária', icon: Icons.today_rounded),
    _RecurrenceOption(value: TaskRecurrence.weekdays, label: 'Dias úteis', icon: Icons.work_outline),
    _RecurrenceOption(value: TaskRecurrence.weekly, label: 'Semanal', icon: Icons.calendar_view_week_outlined),
    _RecurrenceOption(value: TaskRecurrence.monthly, label: 'Mensal', icon: Icons.calendar_month_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in _options)
          AppChoiceChip(
            label: option.label,
            isSelected: option.value == initialRecurrence,
            selectedColor: scheme.primary,
            icon: option.icon,
            onTap: () => onChanged(option.value),
          ),
      ],
    );
  }
}

class _RecurrenceOption {
  const _RecurrenceOption({required this.value, required this.label, required this.icon});
  final TaskRecurrence? value;
  final String label;
  final IconData icon;
}

/// Human-readable label for a recurrence string. Used in the task tile
/// subtitle so the picker doesn't have to expose its internal map.
String recurrenceLabel(TaskRecurrence? recurrence) {
  switch (recurrence) {
    case TaskRecurrence.daily:
      return 'Diariamente';
    case TaskRecurrence.weekdays:
      return 'Dias úteis';
    case TaskRecurrence.weekly:
      return 'Semanalmente';
    case TaskRecurrence.monthly:
      return 'Mensalmente';
    case null:
      return '';
  }
}
