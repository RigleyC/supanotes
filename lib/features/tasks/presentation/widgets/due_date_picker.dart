import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supanotes/shared/widgets/app_choice_chip.dart';

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
        AppChoiceChip(
          label: 'Hoje',
          isSelected: isSelected(today),
          selectedColor: scheme.primary,
          onTap: () => onChanged(today),
        ),
        AppChoiceChip(
          label: 'Amanhã',
          isSelected: isSelected(tomorrow),
          selectedColor: scheme.primary,
          onTap: () => onChanged(tomorrow),
        ),
        AppChoiceChip(
          label: 'Próx. segunda',
          isSelected: isSelected(nextMonday()),
          selectedColor: scheme.primary,
          onTap: () => onChanged(nextMonday()),
        ),
        AppChoiceChip(
          label: initialDate != null && !_isQuickPick(initialDate!, today, tomorrow, nextMonday())
              ? DateFormat('d MMM').format(initialDate!)
              : 'Escolher data',
          isSelected: initialDate != null &&
              !_isQuickPick(initialDate!, today, tomorrow, nextMonday()),
          selectedColor: scheme.primary,
          icon: Icons.calendar_today_outlined,
          onTap: pickCustomDate,
        ),
        AppChoiceChip(
          label: 'Sem data',
          isSelected: initialDate == null,
          selectedColor: scheme.primary,
          icon: Icons.block,
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

