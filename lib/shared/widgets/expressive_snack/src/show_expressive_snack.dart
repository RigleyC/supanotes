import 'package:flutter/material.dart';
import 'snack.dart';
import 'snack_overlay.dart';

void showExpressiveSnack({
  BuildContext? context,
  required String message,
  IconData? icon,
  SnackBarAction? action,
  Duration duration = const Duration(seconds: 4),
}) {
  final snack = Snack(
    message: message,
    icon: icon,
    duration: duration,
    action: action,
  );
  final actual = SnackOverlay.add(snack);

  if (actual != snack) {
    actual.key.currentState?.shake();
  }
}
