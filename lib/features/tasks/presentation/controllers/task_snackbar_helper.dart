import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supanotes/shared/widgets/app_snackbar.dart';

class TaskSnackBarHelper {
  static Future<DateTime?> completeTaskWithFeedback({
    required Future<DateTime?> Function() onComplete,
    required VoidCallback onUndo,
  }) async {
    final nextDue = await onComplete();

    final message = nextDue != null
        ? 'Tarefa concluída! Próx. em: ${DateFormat('pt_BR', 'MMMMd').format(nextDue)}'
        : 'Tarefa concluída!';

    AppMessenger.showAction(
      message,
      action: SnackBarAction(label: 'Desfazer', onPressed: onUndo),
      duration: const Duration(seconds: 5),
    );

    return nextDue;
  }
}
