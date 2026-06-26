import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// A full-width, tappable tile for list-based single-selection UIs.
///
/// Used by [DueDatePicker] and [RecurrencePicker] to replace the old
/// chip-based layout with a more scannable, thumb-friendly vertical list.
class AppSelectionTile extends StatelessWidget {
  const AppSelectionTile({
    super.key,
    required this.label,
    this.icon,
    this.isSelected = false,
    this.onTap,
    this.trailing,
  });

  final String label;
  final IconData? icon;
  final bool isSelected;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ListTile(
      dense: true,
      selected: isSelected,
      onTap: onTap,
      tileColor: Colors.transparent,
      selectedTileColor: scheme.onSurface.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      leading: icon != null
          ? Icon(
              icon,
              size: AppSpacing.iconMd,
              color: isSelected ? scheme.primary : scheme.onSurfaceVariant,
            )
          : null,
      title: Text(
        label,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: isSelected ? scheme.primary : scheme.onSurface,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            ),
      ),
      trailing: isSelected
          ? Icon(
              Icons.check_circle,
              size: AppSpacing.iconSm,
              color: scheme.primary,
            )
          : trailing,
    );
  }
}
