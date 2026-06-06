/// Generic confirmation dialog used across destructive actions.
///
/// Resolves to `true` when the user taps the confirm button and `false`
/// (or `null` — collapsed to `false` by [showConfirmDialog]) on cancel,
/// outside-tap, or back-button dismiss. When [destructive] is `true` the
/// confirm button is rendered in the error color so the user understands
/// the action cannot be silently undone.
library;

import 'package:flutter/material.dart';

import 'package:supanotes/shared/theme/app_spacing.dart';

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
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => ConfirmDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      destructive: destructive,
    ),
  );
  return result ?? false;
}

class ConfirmDialog extends StatelessWidget {
  const ConfirmDialog({
    super.key,
    required this.title,
    required this.message,
    this.confirmLabel = ConfirmDialogStrings.confirm,
    this.cancelLabel = ConfirmDialogStrings.cancel,
    this.destructive = false,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final confirmStyle = destructive
        ? FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          )
        : null;

    return AlertDialog(
      title: Text(title),
      content: Text(message),
      contentPadding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancelLabel),
        ),
        FilledButton(
          style: confirmStyle,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    );
  }
}
