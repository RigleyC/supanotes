import 'package:flutter/material.dart';

import '../../../../shared/theme/app_spacing.dart';

/// 7-chip day-of-week picker (Seg..Dom).
///
/// In [DaySelectorMode.single] exactly one day is always selected —
/// the widget is opinionated and will swap to the tapped chip
/// immediately. In [DaySelectorMode.multi] the user can toggle
/// individual days; callers are responsible for ensuring the result
/// is non-empty (the schedule builder requires at least one day).
class DaySelector extends StatelessWidget {
  const DaySelector({
    super.key,
    required this.selected,
    required this.onChanged,
    this.mode = DaySelectorMode.multi,
  });

  final List<int> selected;
  final ValueChanged<List<int>> onChanged;
  final DaySelectorMode mode;

  static const List<_DayInfo> _days = [
    _DayInfo(1, 'Seg'),
    _DayInfo(2, 'Ter'),
    _DayInfo(3, 'Qua'),
    _DayInfo(4, 'Qui'),
    _DayInfo(5, 'Sex'),
    _DayInfo(6, 'Sáb'),
    _DayInfo(7, 'Dom'),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        for (final day in _days)
          _DayChip(
            label: day.label,
            isSelected: selected.contains(day.value),
            onTap: () => _handleTap(day.value),
          ),
      ],
    );
  }

  void _handleTap(int day) {
    switch (mode) {
      case DaySelectorMode.single:
        if (selected.length == 1 && selected.first == day) return;
        onChanged([day]);
      case DaySelectorMode.multi:
        final next = [...selected];
        if (next.contains(day)) {
          next.remove(day);
        } else {
          next.add(day);
        }
        onChanged(next);
    }
  }
}

enum DaySelectorMode { single, multi }

class _DayInfo {
  const _DayInfo(this.value, this.label);
  final int value;
  final String label;
}

class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final background = isSelected ? scheme.primary : scheme.surfaceContainerHighest;
    final foreground = isSelected ? scheme.onPrimary : scheme.onSurfaceVariant;

    return Material(
      color: background,
      shape: const StadiumBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Text(
            label,
            style: textTheme.labelMedium?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
