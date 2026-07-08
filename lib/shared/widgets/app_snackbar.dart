import 'package:flutter/material.dart';
import 'package:supanotes/shared/widgets/expressive_snack/expressive_snack.dart';

class AppMessenger {
  AppMessenger._();

  static final GlobalKey<ScaffoldMessengerState> key =
      GlobalKey<ScaffoldMessengerState>();

  static void showSuccess(
    String title, {
    String? subtitle,
    SnackBarAction? action,
    Duration? duration,
  }) {
    final context = key.currentContext;
    if (context == null) return;
    showExpressiveSnack(
      context: context,
      message: subtitle != null ? '$title\n$subtitle' : title,
      icon: Icons.check_circle,
      action: action,
      duration: duration ?? const Duration(seconds: 4),
    );
  }

  static void showError(
    String title, {
    String? subtitle,
    SnackBarAction? action,
    Duration? duration,
  }) {
    final context = key.currentContext;
    if (context == null) return;
    showExpressiveSnack(
      context: context,
      message: subtitle != null ? '$title\n$subtitle' : title,
      icon: Icons.error,
      action: action,
      duration: duration ?? const Duration(seconds: 4),
    );
  }

  static void showInfo(
    String title, {
    String? subtitle,
    SnackBarAction? action,
    Duration? duration,
  }) {
    final context = key.currentContext;
    if (context == null) return;
    showExpressiveSnack(
      context: context,
      message: subtitle != null ? '$title\n$subtitle' : title,
      icon: Icons.info,
      action: action,
      duration: duration ?? const Duration(seconds: 4),
    );
  }

  static void showTaskCompletion({
    required String title,
    String? subtitle,
    required SnackBarAction action,
    Duration? duration,
  }) {
    final context = key.currentContext;
    if (context == null) return;
    showExpressiveSnack(
      context: context,
      message: subtitle != null ? '$title\n$subtitle' : title,
      icon: Icons.task_alt,
      action: action,
      duration: duration ?? const Duration(seconds: 3),
    );
  }
}
