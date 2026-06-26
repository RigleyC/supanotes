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

  static const _options = <_RecurrenceOption>[
    _RecurrenceOption(value: null, label: 'Nenhuma', icon: Icons.do_not_disturb_on_outlined),
    _RecurrenceOption(value: TaskRecurrence.daily, label: 'Diária', icon: Icons.today_rounded),
    _RecurrenceOption(value: TaskRecurrence.weekdays, label: 'Dias úteis', icon: Icons.work_outline),
    _RecurrenceOption(value: TaskRecurrence.weekly, label: 'Semanal', icon: Icons.calendar_view_week_outlined),
    _RecurrenceOption(value: TaskRecurrence.monthly, label: 'Mensal', icon: Icons.calendar_month_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final option in _options)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppSelectionTile(
              label: option.label,
              icon: option.icon,
              isSelected: option.value == initialRecurrence,
              onTap: () => onChanged(option.value),
            ),
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

String recurrenceLabel(TaskRecurrence? recurrence) {
  switch (recurrence) {
    case TaskRecurrence.daily:
      return 'Diariamente';
    case TaskRecurrence.weekdays:
      return 'Dias uteis';
    case TaskRecurrence.weekly:
      return 'Semanalmente';
    case TaskRecurrence.monthly:
      return 'Mensalmente';
    case null:
      return '';
  }
}
