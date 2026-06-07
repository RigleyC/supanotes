import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

class AppChoiceChip extends StatelessWidget {
  const AppChoiceChip({
    super.key,
    required this.label,
    this.icon,
    this.isSelected = false,
    this.selectedColor,
    this.onTap,
  });

  final String label;
  final IconData? icon;
  final bool isSelected;
  final Color? selectedColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = isSelected
        ? (selectedColor ?? scheme.primaryContainer)
        : scheme.surfaceContainerHighest;
    final fg = isSelected
        ? (selectedColor != null ? scheme.onPrimary : scheme.onPrimaryContainer)
        : scheme.onSurfaceVariant;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: AppSpacing.iconSm,
                  color: fg,
                ),
                const SizedBox(width: AppSpacing.xs),
              ],
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (isSelected) ...[
                const SizedBox(width: AppSpacing.xs),
                Icon(
                  Icons.check,
                  size: AppSpacing.iconSm,
                  color: fg,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
