import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

class AppChoiceChip extends StatelessWidget {
  const AppChoiceChip({
    super.key,
    required this.label,
    this.icon,
    this.isSelected = false,
    this.onTap,
  });

  final String label;
  final IconData? icon;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: isSelected ? scheme.primaryContainer : scheme.surfaceContainerHighest,
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
                  size: 18,
                  color: isSelected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.xs),
              ],
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: isSelected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
                ),
              ),
              if (isSelected) ...[
                const SizedBox(width: AppSpacing.xs),
                Icon(
                  Icons.check,
                  size: 16,
                  color: scheme.onPrimaryContainer,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
