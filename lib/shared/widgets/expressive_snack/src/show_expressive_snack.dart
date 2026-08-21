import 'package:flutter/material.dart';
import 'package:supanotes/core/utils/app_haptics.dart';
import 'package:supanotes/shared/widgets/expressive_snack/src/snack.dart';
import 'package:supanotes/shared/widgets/expressive_snack/src/snack_overlay.dart';

void showExpressiveSnack({
  required String title, BuildContext? context,
  String? subtitle,
  IconData? icon,
  SnackBarAction? action,
  Duration duration = const Duration(seconds: 4),
}) {
  AppHaptics.snackbar();
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
