import 'package:flutter/material.dart';
import 'package:supanotes/core/utils/app_haptics.dart';

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
    final scheme = Theme.of(context).colorScheme;
    final child = _AppButtonContent(
      text: text,
      icon: icon,
      variant: variant,
      isLoading: isLoading,
      foregroundColor: _foregroundColor(scheme),
      fabForegroundColor: scheme.onPrimary,
    );
    final button = _AppButtonControl(
      variant: variant,
      isLoading: isLoading,
      onPressed: onPressed,
      scheme: scheme,
      child: child,
    );
    return _AppButtonLayout(variant: variant, width: width, child: button);
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

class _AppButtonContent extends StatelessWidget {
  const _AppButtonContent({
    required this.text,
    required this.icon,
    required this.variant,
    required this.isLoading,
    required this.foregroundColor,
    required this.fabForegroundColor,
  });

  final String? text;
  final Widget? icon;
  final AppButtonVariant variant;
  final bool isLoading;
  final Color foregroundColor;
  final Color fabForegroundColor;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return SizedBox(
        height: 20,
        width: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: variant == AppButtonVariant.fab
              ? fabForegroundColor
              : foregroundColor,
        ),
      );
    }
    if (variant == AppButtonVariant.fab) {
      return icon ?? Icon(Icons.add, color: fabForegroundColor);
    }
    if (icon != null && text != null && text!.isNotEmpty) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [icon!, const SizedBox(width: 8), Text(text!)],
      );
    }
    return icon ?? Text(text ?? '');
  }
}

class _AppButtonControl extends StatelessWidget {
  const _AppButtonControl({
    required this.variant,
    required this.isLoading,
    required this.onPressed,
    required this.scheme,
    required this.child,
  });

  final AppButtonVariant variant;
  final bool isLoading;
  final VoidCallback? onPressed;
  final ColorScheme scheme;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    const size = Size(0, 48);
    final callback = isLoading || onPressed == null
        ? null
        : () {
            AppHaptics.controlTap();
            onPressed!();
          };
    return switch (variant) {
      AppButtonVariant.primary => FilledButton(
        onPressed: callback,
        style: FilledButton.styleFrom(minimumSize: size),
        child: child,
      ),
      AppButtonVariant.secondary => OutlinedButton(
        onPressed: callback,
        style: OutlinedButton.styleFrom(minimumSize: size),
        child: child,
      ),
      AppButtonVariant.tonal => FilledButton.tonal(
        onPressed: callback,
        style: FilledButton.styleFrom(minimumSize: size),
        child: child,
      ),
      AppButtonVariant.danger => FilledButton(
        onPressed: callback,
        style: FilledButton.styleFrom(
          minimumSize: size,
          backgroundColor: scheme.error,
          foregroundColor: scheme.onError,
        ),
        child: child,
      ),
      AppButtonVariant.text => TextButton(
        onPressed: callback,
        style: TextButton.styleFrom(minimumSize: size),
        child: child,
      ),
      AppButtonVariant.fab => FloatingActionButton(
        shape: const CircleBorder(),
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        onPressed: callback,
        child: IconTheme(
          data: IconThemeData(color: scheme.onPrimary),
          child: child,
        ),
      ),
    };
  }
}

class _AppButtonLayout extends StatelessWidget {
  const _AppButtonLayout({
    required this.variant,
    required this.width,
    required this.child,
  });

  final AppButtonVariant variant;
  final double? width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (variant == AppButtonVariant.fab && width == null) return child;
    return SizedBox(
      width: variant == AppButtonVariant.fab ? width : width ?? double.infinity,
      child: child,
    );
  }
}
