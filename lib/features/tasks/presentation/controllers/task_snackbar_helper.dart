import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supanotes/shared/widgets/app_snackbar.dart';

class TaskSnackBarHelper {
  static Future<DateTime?> completeTaskWithFeedback({
    required Future<DateTime?> Function() onComplete,
    required VoidCallback onUndo,
  }) async {
    final nextDue = await onComplete();

    final title = 'Concluída!';
    final subtitle = nextDue != null
        ? 'Próx. em: ${DateFormat.MMMMd('pt_BR').format(nextDue)}'
        : null;

    AppMessenger.showTaskCompletion(
      title: title,
      subtitle: subtitle,
      action: SnackBarAction(label: 'Desfazer', onPressed: onUndo),
    );

    return nextDue;
  }
}
