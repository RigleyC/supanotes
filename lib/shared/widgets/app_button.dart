import 'package:flutter/material.dart';

enum AppButtonVariant { primary, secondary, tonal, danger, text }

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.variant = AppButtonVariant.primary,
    this.width,
    this.icon,
  });

  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final AppButtonVariant variant;
  final double? width;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Widget child;
    if (isLoading) {
      child = SizedBox(
        height: 20,
        width: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: _foregroundColor(scheme),
        ),
      );
    } else if (icon != null) {
      child = Row(
        mainAxisSize: MainAxisSize.min,
        children: [icon!, const SizedBox(width: 8), Text(text)],
      );
    } else {
      child = Text(text);
    }

    const size = Size(0, 48);

    Widget button = switch (variant) {
      AppButtonVariant.primary => FilledButton(
        onPressed: isLoading ? null : onPressed,
        style: FilledButton.styleFrom(minimumSize: size),
        child: child,
      ),
      AppButtonVariant.secondary => OutlinedButton(
        onPressed: isLoading ? null : onPressed,
        style: OutlinedButton.styleFrom(minimumSize: size),
        child: child,
      ),
      AppButtonVariant.tonal => FilledButton.tonal(
        onPressed: isLoading ? null : onPressed,
        style: FilledButton.styleFrom(minimumSize: size),
        child: child,
      ),
      AppButtonVariant.danger => FilledButton(
        onPressed: isLoading ? null : onPressed,
        style: FilledButton.styleFrom(
          minimumSize: size,
          backgroundColor: scheme.error,
          foregroundColor: scheme.onError,
        ),
        child: child,
      ),
      AppButtonVariant.text => TextButton(
        onPressed: isLoading ? null : onPressed,
        style: TextButton.styleFrom(minimumSize: size),
        child: child,
      ),
    };

    return SizedBox(width: width ?? double.infinity, child: button);
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
      case AppButtonVariant.text:
        return scheme.primary;
    }
  }
}
