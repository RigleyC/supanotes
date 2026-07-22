import 'package:flutter/material.dart';

enum AppButtonVariant { primary, secondary, tonal, danger, text, fab }

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    this.text,
    this.onPressed,
    this.isLoading = false,
    this.variant = AppButtonVariant.primary,
    this.width,
    this.icon,
  });

  final String? text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final AppButtonVariant variant;
  final double? width;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final fabBgColor = isDark ? Colors.white : Colors.black;
    final fabFgColor = isDark ? Colors.black : Colors.white;

    final Widget child;
    if (isLoading) {
      child = SizedBox(
        height: 20,
        width: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: variant == AppButtonVariant.fab
              ? fabFgColor
              : _foregroundColor(scheme),
        ),
      );
    } else if (variant == AppButtonVariant.fab) {
      child = icon ?? Icon(Icons.add, color: fabFgColor);
    } else if (icon != null && text != null && text!.isNotEmpty) {
      child = Row(
        mainAxisSize: MainAxisSize.min,
        children: [icon!, const SizedBox(width: 8), Text(text!)],
      );
    } else if (icon != null) {
      child = icon!;
    } else {
      child = Text(text ?? '');
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
      AppButtonVariant.fab => FloatingActionButton(
        shape: const CircleBorder(),
        backgroundColor: fabBgColor,
        foregroundColor: fabFgColor,
        onPressed: isLoading ? null : onPressed,
        child: IconTheme(
          data: IconThemeData(color: fabFgColor),
          child: child,
        ),
      ),
    };

    if (variant == AppButtonVariant.fab) {
      if (width != null) {
        return SizedBox(width: width, child: button);
      }
      return button;
    }

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
      case AppButtonVariant.fab:
        return scheme.onPrimary;
    }
  }
}
