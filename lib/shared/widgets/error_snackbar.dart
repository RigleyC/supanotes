import 'package:flutter/material.dart';

/// Shows a styled error [SnackBar] via [ScaffoldMessenger].
///
/// The snack bar uses [ColorScheme.error] as its background, displays
/// [message] with an [Icons.error_outline] leading icon, and — when
/// [onRetry] is provided — adds a "Tentar novamente" action.
void showErrorSnackBar(
  BuildContext context, {
  required String message,
  VoidCallback? onRetry,
}) {
  final scheme = Theme.of(context).colorScheme;
  final textTheme = Theme.of(context).textTheme;

  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              Icons.error_outline,
              color: scheme.onError,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: textTheme.bodyMedium?.copyWith(
                  color: scheme.onError,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: scheme.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        action: onRetry != null
            ? SnackBarAction(
                label: 'Tentar novamente',
                textColor: scheme.onError,
                onPressed: onRetry,
              )
            : null,
      ),
    );
}
