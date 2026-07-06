import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supanotes/shared/widgets/app_snackbar.dart';

class TaskSnackBarHelper {
  static Future<DateTime?> completeTaskWithFeedback({
    required Future<({DateTime? nextDue, DateTime? previousDue})> Function() onComplete,
    required void Function(DateTime? previousDue) onUndo,
  }) async {
    final result = await onComplete();

    final title = 'Concluída!';
    final subtitle = result.nextDue != null
        ? 'Próx. em: ${DateFormat.MMMMd('pt_BR').format(result.nextDue!)}'
        : null;

    AppMessenger.showTaskCompletion(
      title: title,
      subtitle: subtitle,
      action: SnackBarAction(
        label: 'Desfazer',
        onPressed: () {
          debugPrint('[TaskSnackBarHelper] onUndo PRESSED, previousDue=${result.previousDue}');
          onUndo(result.previousDue);
        },
      ),
    );

    return result.nextDue;
  }
}
