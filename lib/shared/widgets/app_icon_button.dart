import 'package:flutter/material.dart';

/// Shared icon-only action control.
///
/// Keeping icon actions behind the shared widget makes their hit target and
/// interaction style explicit without forcing them into a text-button layout.
class AppIconButton extends StatelessWidget {
  final Widget icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final BoxConstraints? constraints;
  final EdgeInsetsGeometry? padding;
  final VisualDensity? visualDensity;

  const AppIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.constraints,
    this.padding,
    this.visualDensity,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: icon,
      onPressed: onPressed,
      tooltip: tooltip,
      constraints: constraints,
      padding: padding,
      visualDensity: visualDensity,
    );
  }
}
