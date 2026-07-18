import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supanotes/shared/widgets/app_snackbar.dart';

class TaskSnackBarHelper {
  static Future<DateTime?> completeTaskWithFeedback({
    required Future<({DateTime? nextDue, DateTime? previousDue, bool previousHasTime})> Function() onComplete,
    required void Function(DateTime? previousDue, bool previousHasTime) onUndo,
  }) async {
    debugPrint('[TaskSnackBarHelper] completeTaskWithFeedback CALLED');
    final result = await onComplete();
    debugPrint('[TaskSnackBarHelper] onComplete returned nextDue=${result.nextDue}');

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
          onUndo(result.previousDue, result.previousHasTime);
        },
      ),
    );

    return result.nextDue;
  }
}
