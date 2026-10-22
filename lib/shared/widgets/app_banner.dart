import 'package:flutter/material.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';

/// Inline banner for contextual messages that belong to the screen body.
///
/// Keeps the message, its leading icon and an optional action in one row so
/// features do not rebuild the same surface with different colors.
class AppBanner extends StatelessWidget {
  const AppBanner({
    required this.message,
    super.key,
    this.icon = Icons.info_outline,
    this.action,
    this.isError = false,
  });

  final String message;
  final IconData icon;
  final Widget? action;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = isError
        ? scheme.errorContainer
        : scheme.secondaryContainer;
    final foreground = isError
        ? scheme.onErrorContainer
        : scheme.onSecondaryContainer;

    return Material(
      color: background,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            Icon(icon, size: AppSpacing.iconMd, color: foreground),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                message,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: foreground),
              ),
            ),
            if (action != null) ...[
              const SizedBox(width: AppSpacing.sm),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
