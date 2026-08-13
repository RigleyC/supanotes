import 'package:flutter/material.dart';
import 'package:supanotes/core/utils/app_haptics.dart';

/// A full-width, tappable tile for list-based single-selection UIs.
///
/// Used by task metadata selection pages for a scannable, thumb-friendly
/// vertical list.
class AppSelectionTile extends StatelessWidget {
  const AppSelectionTile({
    super.key,
    required this.label,
    this.icon,
    this.leading,
    this.isSelected = false,
    this.onTap,
    this.trailing,
    this.selectedTrailing,
  });

  final String label;
  final IconData? icon;
  final Widget? leading;
  final bool isSelected;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Widget? selectedTrailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final callback = onTap == null
        ? null
        : () {
            if (!isSelected) {
              AppHaptics.selectionChange();
            }
            onTap!();
          };

    return ListTile(
      dense: true,
      selected: isSelected,
      onTap: callback,
      leading:
          leading ??
          (icon != null
              ? Icon(
                  icon,
                  size: 20,
                  color: isSelected ? scheme.primary : scheme.onSurfaceVariant,
                )
              : null),
      title: Text(
        label,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: isSelected ? scheme.primary : scheme.onSurface,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
      trailing: isSelected
          ? (selectedTrailing ??
                Icon(Icons.check_rounded, size: 20, color: scheme.primary))
          : trailing,
    );
  }
}
