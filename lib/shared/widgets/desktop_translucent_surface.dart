import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:supanotes/shared/theme/desktop_layout_tokens.dart';

/// Applies the translucent, blurred surface used by the desktop shell.
class DesktopTranslucentSurface extends StatelessWidget {
  final Widget child;
  final Color color;

  const DesktopTranslucentSurface({
    super.key,
    required this.child,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: DesktopLayoutTokens.surfaceBlurSigma,
          sigmaY: DesktopLayoutTokens.surfaceBlurSigma,
        ),
        child: ColoredBox(
          color: color.withValues(alpha: DesktopLayoutTokens.surfaceOpacity),
          child: child,
        ),
      ),
    );
  }
}
