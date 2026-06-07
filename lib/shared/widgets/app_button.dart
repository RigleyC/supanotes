import 'package:flutter/material.dart';

enum AppButtonVariant { primary, secondary, tonal, danger }

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.variant = AppButtonVariant.primary,
    this.width,
  });

  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final AppButtonVariant variant;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final child = isLoading
        ? SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: _foregroundColor(scheme),
            ),
          )
        : Text(text);

    final size = Size(width ?? double.infinity, 48);

    switch (variant) {
      case AppButtonVariant.primary:
        return FilledButton(
          onPressed: isLoading ? null : onPressed,
          style: FilledButton.styleFrom(minimumSize: size),
          child: child,
        );
      case AppButtonVariant.secondary:
        return OutlinedButton(
          onPressed: isLoading ? null : onPressed,
          style: OutlinedButton.styleFrom(minimumSize: size),
          child: child,
        );
      case AppButtonVariant.tonal:
        return FilledButton.tonal(
          onPressed: isLoading ? null : onPressed,
          style: FilledButton.styleFrom(minimumSize: size),
          child: child,
        );
      case AppButtonVariant.danger:
        return FilledButton(
          onPressed: isLoading ? null : onPressed,
          style: FilledButton.styleFrom(
            minimumSize: size,
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          child: child,
        );
    }
  }

  Color _foregroundColor(ColorScheme scheme) {
    switch (variant) {
      case AppButtonVariant.primary:
        return scheme.onPrimary;
      case AppButtonVariant.secondary:
        return scheme.primary;
      case AppButtonVariant.tonal:
        return scheme.onSecondaryContainer;
      case AppButtonVariant.danger:
        return scheme.onError;
    }
  }
}
