import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/widgets/app_platform_icon_button.dart';
import 'package:supanotes/shared/widgets/confirm_dialog.dart';

/// The task editor modal with native actions and keyboard-aware spacing.
class TaskEditorSheet extends StatelessWidget {
  const TaskEditorSheet({
    required this.child,
    required this.onCancel,
    required this.onSave,
    this.onDelete,
    this.isSaving = false,
    super.key,
  });

  final Widget child;
  final VoidCallback onCancel;
  final Future<void> Function() onSave;
  final Future<void> Function()? onDelete;
  final bool isSaving;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final content = SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: child,
    );
    final dismissible = onDelete == null
        ? content
        : Dismissible(
            key: const ValueKey('task-editor-dismissible'),
            direction: DismissDirection.endToStart,
            background: const SizedBox.shrink(),
            secondaryBackground: ColoredBox(
              color: scheme.errorContainer,
              child: Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: EdgeInsets.only(right: AppSpacing.lg),
                  child: Icon(
                    Icons.delete_outline_rounded,
                    color: scheme.onErrorContainer,
                  ),
                ),
              ),
            ),
            confirmDismiss: (_) async {
              if (isSaving) return false;
              final confirmed = await showConfirmDialog(
                context: context,
                title: 'Excluir task?',
                message: 'Essa task será removida da sua lista.',
                confirmLabel: 'Excluir',
                destructive: true,
              );
              if (!confirmed) return false;
              await onDelete!();
              return false;
            },
            child: content,
          );

    return Material(
      type: MaterialType.transparency,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.sm,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: Row(
                children: [
                  AppPlatformIconButton(
                    icon: Icons.close_rounded,
                    tooltip: 'Fechar',
                    onPressed: isSaving ? null : onCancel,
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        'Criar/Editar nota',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ),
                  AppPlatformIconButton(
                    icon: Icons.check_rounded,
                    tooltip: 'Salvar',
                    onPressed: isSaving ? null : () => unawaited(onSave()),
                  ),
                ],
              ),
            ),
            dismissible,
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }
}
