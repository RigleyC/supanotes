/// Generic confirmation dialog used across destructive actions.
///
/// Resolves to `true` when the user taps the confirm button and `false`
/// (or `null` — collapsed to `false` by [showConfirmDialog]) on cancel,
/// outside-tap, or back-button dismiss. When [destructive] is `true` the
/// confirm button is rendered in the error color so the user understands
/// the action cannot be silently undone.
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supanotes/core/utils/app_haptics.dart';
import 'package:supanotes/shared/widgets/app_button.dart';

/// Strings displayed inside the confirm dialog.
///
/// Centralised here so feature code never has to repeat the same Portuguese
/// labels for "Cancelar" / "Confirmar".
class ConfirmDialogStrings {
  ConfirmDialogStrings._();

  static const String cancel = 'Cancelar';
  static const String confirm = 'Confirmar';
}

/// Shows a modal confirmation dialog and returns whether the user confirmed.
///
/// Returns `false` for every dismiss path other than tapping the confirm
/// button so callers can `if (confirmed) { ... }` without a null-check.
Future<bool> showConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  String confirmLabel = ConfirmDialogStrings.confirm,
  String cancelLabel = ConfirmDialogStrings.cancel,
  bool destructive = false,
}) async {
  final isApple =
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;
  final result = isApple
      ? await showCupertinoDialog<bool>(
          context: context,
          builder: (dialogContext) => CupertinoAlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              CupertinoDialogAction(
                onPressed: () {
                  AppHaptics.controlTap();
                  Navigator.pop(dialogContext, false);
                },
                child: Text(cancelLabel),
              ),
              CupertinoDialogAction(
                isDestructiveAction: destructive,
                onPressed: () {
                  AppHaptics.controlTap();
                  Navigator.pop(dialogContext, true);
                },
                child: Text(confirmLabel),
              ),
            ],
          ),
        )
      : await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              AppButton(
                text: cancelLabel,
                variant: AppButtonVariant.text,
                onPressed: () {
                  AppHaptics.controlTap();
                  Navigator.pop(dialogContext, false);
                },
              ),
              AppButton(
                text: confirmLabel,
                variant: destructive
                    ? AppButtonVariant.danger
                    : AppButtonVariant.text,
                onPressed: () {
                  AppHaptics.controlTap();
                  Navigator.pop(dialogContext, true);
                },
              ),
            ],
          ),
        );
  return result ?? false;
}
