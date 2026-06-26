import 'package:flutter/material.dart';

class AppMessenger {
  AppMessenger._();

  static final GlobalKey<ScaffoldMessengerState> key =
      GlobalKey<ScaffoldMessengerState>();

  static void showSuccess(String message, {Duration? duration}) {
    _show(
      message,
      backgroundColor: Colors.green.shade700,
      duration: duration,
    );
  }

  static void showError(
    String message, {
    VoidCallback? onRetry,
    Duration? duration,
  }) {
    _show(
      message,
      backgroundColor: Colors.red.shade700,
      duration: duration,
      action: onRetry != null
          ? SnackBarAction(label: 'Tentar novamente', onPressed: onRetry)
          : null,
    );
  }

  static void showInfo(String message, {Duration? duration}) {
    _show(message, duration: duration);
  }

  static void showAction(
    String message, {
    required SnackBarAction action,
    Duration? duration,
  }) {
    _show(message, duration: duration, action: action);
  }

  static void _show(
    String message, {
    Color? backgroundColor,
    Duration? duration,
    SnackBarAction? action,
  }) {
    final messenger = key.currentState;
    if (messenger == null) return;

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: backgroundColor,
          behavior: SnackBarBehavior.floating,
          duration: duration ?? const Duration(seconds: 4),
          action: action,
        ),
      );
  }
}
