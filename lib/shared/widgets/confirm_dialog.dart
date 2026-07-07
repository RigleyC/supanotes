/// Generic confirmation dialog used across destructive actions.
///
/// Resolves to `true` when the user taps the confirm button and `false`
/// (or `null` — collapsed to `false` by [showConfirmDialog]) on cancel,
/// outside-tap, or back-button dismiss. When [destructive] is `true` the
/// confirm button is rendered in the error color so the user understands
/// the action cannot be silently undone.
library;

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';


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
  bool? confirmed;
  await AdaptiveAlertDialog.show(
    context: context,
    title: title,
    message: message,
    actions: [
      AlertAction(
        title: cancelLabel,
        style: AlertActionStyle.cancel,
        onPressed: () => confirmed = false,
      ),
      AlertAction(
        title: confirmLabel,
        style: destructive ? AlertActionStyle.destructive : AlertActionStyle.primary,
        onPressed: () => confirmed = true,
      ),
    ],
  );
  return confirmed ?? false;
}
