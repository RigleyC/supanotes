import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class AppMessenger {
  AppMessenger._();

  static void showSuccess(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
      ));
  }

  static void showError(
    BuildContext context,
    String message, {
    VoidCallback? onRetry,
  }) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
        behavior: SnackBarBehavior.floating,
        action: onRetry != null
            ? SnackBarAction(
                label: 'Tentar novamente',
                onPressed: onRetry,
              )
            : null,
      ));
  }

  static void showInfo(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ));
  }

  /// Completes a task and shows a snackbar with "Desfazer" action.
  /// Returns the next due date for recurring tasks.
  static Future<DateTime?> completeTaskWithFeedback(
    BuildContext context, {
    required Future<DateTime?> Function() onComplete,
    required VoidCallback onUndo,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final nextDue = await onComplete();

    final message = nextDue != null
        ? 'Tarefa concluída! Próx. ocorrência: ${DateFormat('dd/MM/yyyy').format(nextDue)}'
        : 'Tarefa concluída!';

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Desfazer',
          textColor: Colors.white,
          onPressed: onUndo,
        ),
      ));

    return nextDue;
  }
}
