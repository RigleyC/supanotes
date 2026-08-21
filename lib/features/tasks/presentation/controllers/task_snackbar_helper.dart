import 'package:flutter/material.dart';
import 'package:supanotes/shared/widgets/app_snackbar.dart';

class TaskSnackBarHelper {
  static Future<DateTime?> completeTaskWithFeedback({
    required Future<
      ({
        DateTime? nextDue,
        DateTime? previousDue,
        bool previousHasTime,
        DateTime? scheduledAt,
      })
    >
    Function()
    onComplete,
    required void Function(
      DateTime? previousDue,
      bool previousHasTime,
      DateTime? scheduledAt,
    )
    onUndo,
  }) async {
    debugPrint('[TaskSnackBarHelper] completeTaskWithFeedback CALLED');
    final result = await onComplete();
    debugPrint('[TaskSnackBarHelper] onComplete returned');

    const title = 'Concluída!';

    AppMessenger.showTaskCompletion(
      title: title,
      action: SnackBarAction(
        label: 'Desfazer',
        onPressed: () {
          debugPrint(
            '[TaskSnackBarHelper] onUndo PRESSED, previousDue=${result.previousDue}',
          );
          onUndo(
            result.previousDue,
            result.previousHasTime,
            result.scheduledAt,
          );
        },
      ),
    );

    return result.nextDue;
  }
}
