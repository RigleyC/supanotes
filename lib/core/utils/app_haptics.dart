import 'package:flutter/services.dart';

abstract final class AppHaptics {
  static Future<void> controlTap() => HapticFeedback.lightImpact();

  static Future<void> selectionChange() => HapticFeedback.selectionClick();

  static Future<void> taskCompletion() => HapticFeedback.mediumImpact();
}
