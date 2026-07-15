import 'package:flutter/material.dart';
import 'snack.dart';
import 'snack_overlay.dart';

void showExpressiveSnack({
  BuildContext? context,
  required String title,
  String? subtitle,
  IconData? icon,
  SnackBarAction? action,
  Duration duration = const Duration(seconds: 4),
}) {
  final snack = Snack(
    title: title,
    subtitle: subtitle,
    icon: icon,
    duration: duration,
    action: action,
  );
  final actual = SnackOverlay.add(snack);

  if (actual != snack) {
    actual.key.currentState?.shake();
  }
}
