import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';

const double kDesktopBreakpoint = 900.0;

bool isDesktopPlatform() {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.linux;
}

bool isDesktopLayout(BuildContext context) {
  return MediaQuery.sizeOf(context).width >= kDesktopBreakpoint;
}
