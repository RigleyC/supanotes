import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// An icon button that uses the native Apple control when available.
class AppPlatformIconButton extends StatelessWidget {
  const AppPlatformIconButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.color,
    this.size = 44,
    super.key,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final isApple =
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
    final button = isApple
        ? CNButton.icon(
            customIcon: icon,
            tint: color,
            config: CNButtonConfig(
              style: CNButtonStyle.plain,
              width: size,
              minHeight: size,
              padding: EdgeInsets.zero,
            ),
            onPressed: onPressed,
          )
        : IconButton(
            icon: Icon(icon, color: color),
            onPressed: onPressed,
            constraints: BoxConstraints.tightFor(width: size, height: size),
            padding: EdgeInsets.zero,
          );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}
