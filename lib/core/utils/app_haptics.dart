import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

abstract final class AppHaptics {
  static Future<void> controlTap() => HapticFeedback.lightImpact();

  static Future<void> selectionChange() => HapticFeedback.selectionClick();

  static Future<void> taskCompletion() => HapticFeedback.mediumImpact();

  static void longPress(BuildContext context) {
    Feedback.forLongPress(context);
  }
}
