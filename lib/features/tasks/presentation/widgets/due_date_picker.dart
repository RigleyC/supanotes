import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Quick-pick chips for setting a task's `dueDate`.
///
/// Renders a `Wrap` of chips the user can tap to set the due date in
/// one tap: "Hoje", "Amanhã", "Próx. segunda", "Escolher data" (opens
/// the native date picker) and "Sem data" (clears the field). The
/// currently selected option is highlighted with the theme primary
/// color and a check icon.
class DueDatePicker extends StatelessWidget {
  const DueDatePicker({
    super.key,
    required this.initialDate,
    required this.onChanged,
  });

  final DateTime? initialDate;
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = DateTime(now.year, now.month, now.day + 1);

    DateTime nextMonday() {
      var d = DateTime(now.year, now.month, now.day + 1);
      while (d.weekday != DateTime.monday) {
        d = DateTime(d.year, d.month, d.day + 1);
      }
      return d;
    }

    bool isSelected(DateTime? value) {
      if (value == null && initialDate == null) return true;
      if (value == null || initialDate == null) return false;
      return value.year == initialDate!.year &&
          value.month == initialDate!.month &&
          value.day == initialDate!.day;
    }

    Future<void> pickCustomDate() async {
      final picked = await showDatePicker(
        context: context,
        initialDate: initialDate ?? today,
        firstDate: DateTime(now.year - 1),
        lastDate: DateTime(now.year + 5),
      );
      if (picked != null) onChanged(picked);
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _Chip(
          label: 'Hoje',
          selected: isSelected(today),
          selectedColor: scheme.primary,
          onTap: () => onChanged(today),
        ),
        _Chip(
          label: 'Amanhã',
          selected: isSelected(tomorrow),
          selectedColor: scheme.primary,
          onTap: () => onChanged(tomorrow),
        ),
        _Chip(
          label: 'Próx. segunda',
          selected: isSelected(nextMonday()),
          selectedColor: scheme.primary,
          onTap: () => onChanged(nextMonday()),
        ),
        _Chip(
          label: initialDate != null && !_isQuickPick(initialDate!, today, tomorrow, nextMonday())
              ? DateFormat('d MMM').format(initialDate!)
              : 'Escolher data',
          selected: initialDate != null &&
              !_isQuickPick(initialDate!, today, tomorrow, nextMonday()),
          selectedColor: scheme.primary,
          leading: const Icon(Icons.calendar_today_outlined, size: 16),
          onTap: pickCustomDate,
        ),
        _Chip(
          label: 'Sem data',
          selected: initialDate == null,
          selectedColor: scheme.primary,
          leading: const Icon(Icons.block, size: 16),
          onTap: () => onChanged(null),
        ),
      ],
    );
  }

  bool _isQuickPick(
    DateTime value,
    DateTime today,
    DateTime tomorrow,
    DateTime nextMonday,
  ) {
    bool same(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;
    return same(value, today) ||
        same(value, tomorrow) ||
        same(value, nextMonday);
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.selectedColor,
    required this.onTap,
    this.leading,
  });

  final String label;
  final bool selected;
  final Color selectedColor;
  final VoidCallback onTap;
  final Widget? leading;

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
              if (leading != null) ...[
                IconTheme(
                  data: IconThemeData(size: 16, color: fg),
                  child: leading!,
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
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
