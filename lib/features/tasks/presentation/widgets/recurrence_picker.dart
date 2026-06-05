import 'package:flutter/material.dart';

/// Chip-based picker for the `recurrence` column.
///
/// Renders five options ("Nenhuma", "Diária", "Dias úteis", "Semanal",
/// "Mensal") and emits the lowercase English string the DAO expects on
/// the backend: `null`, `daily`, `weekdays`, `weekly`, `monthly`. The
/// selected chip is highlighted with the theme primary color and a
/// check icon.
class RecurrencePicker extends StatelessWidget {
  const RecurrencePicker({
    super.key,
    required this.initialRecurrence,
    required this.onChanged,
  });

  final String? initialRecurrence;
  final ValueChanged<String?> onChanged;

  static const _options = <_RecurrenceOption>[
    _RecurrenceOption(value: null, label: 'Nenhuma', icon: Icons.do_not_disturb_on_outlined),
    _RecurrenceOption(value: 'daily', label: 'Diária', icon: Icons.today_outlined),
    _RecurrenceOption(value: 'weekdays', label: 'Dias úteis', icon: Icons.work_outline),
    _RecurrenceOption(value: 'weekly', label: 'Semanal', icon: Icons.calendar_view_week_outlined),
    _RecurrenceOption(value: 'monthly', label: 'Mensal', icon: Icons.calendar_month_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in _options)
          _RecurrenceChip(
            option: option,
            selected: option.value == initialRecurrence,
            selectedColor: scheme.primary,
            onTap: () => onChanged(option.value),
          ),
      ],
    );
  }
}

class _RecurrenceOption {
  const _RecurrenceOption({required this.value, required this.label, required this.icon});
  final String? value;
  final String label;
  final IconData icon;
}

class _RecurrenceChip extends StatelessWidget {
  const _RecurrenceChip({
    required this.option,
    required this.selected,
    required this.selectedColor,
    required this.onTap,
  });

  final _RecurrenceOption option;
  final bool selected;
  final Color selectedColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = selected ? selectedColor : scheme.surfaceContainerHighest;
    final fg = selected ? scheme.onPrimary : scheme.onSurfaceVariant;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(option.icon, size: 16, color: fg),
              const SizedBox(width: 6),
              Text(
                option.label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: fg,
                      fontWeight: FontWeight.w500,
                    ),
              ),
              if (selected) ...[
                const SizedBox(width: 6),
                Icon(Icons.check, size: 16, color: fg),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Human-readable label for a recurrence string. Used in the task tile
/// subtitle so the picker doesn't have to expose its internal map.
String recurrenceLabel(String? recurrence) {
  switch (recurrence) {
    case 'daily':
      return 'Diariamente';
    case 'weekdays':
      return 'Dias úteis';
    case 'weekly':
      return 'Semanalmente';
    case 'monthly':
      return 'Mensalmente';
    default:
      return '';
  }
}
