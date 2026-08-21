import 'package:flutter/material.dart';
import 'package:supanotes/core/utils/app_haptics.dart';

/// Shared icon-only action control.
///
/// Keeping icon actions behind the shared widget makes their hit target and
/// interaction style explicit without forcing them into a text-button layout.
class AppIconButton extends StatelessWidget {

  const AppIconButton({
    required this.icon, required this.onPressed, super.key,
    this.tooltip,
    this.constraints,
    this.padding,
    this.visualDensity,
  });
  final Widget icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final BoxConstraints? constraints;
  final EdgeInsetsGeometry? padding;
  final VisualDensity? visualDensity;

  @override
  Widget build(BuildContext context) {
    final callback = onPressed == null
        ? null
        : () {
            AppHaptics.controlTap();
            onPressed!();
          };

    return IconButton(
      icon: icon,
      onPressed: callback,
      tooltip: tooltip,
      constraints: constraints,
      padding: padding,
      visualDensity: visualDensity,
    );
  }
}
