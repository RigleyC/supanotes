import 'package:flutter/material.dart';

import 'package:supanotes/shared/theme/app_spacing.dart';

class TelegramLinkedView extends StatelessWidget {
  const TelegramLinkedView({
    super.key,
    required this.username,
    this.chatId,
    this.onDelete,
    this.isDeleting = false,
    this.deleteError,
  });

  final String? username;
  final int? chatId;
  final VoidCallback? onDelete;
  final bool isDeleting;
  final String? deleteError;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: AppSpacing.lg),
            const Icon(Icons.check_circle_outline, size: 72),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Telegram conectado',
              style: textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
            Card(
              child: ListTile(
                leading: const Icon(Icons.alternate_email),
                title: const Text('Usuário'),
                subtitle: Text(
                  username ?? '(sem username)',
                  style: textTheme.bodyLarge,
                ),
              ),
            ),
            if (chatId != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.tag),
                  title: const Text('Chat ID'),
                  subtitle: Text(
                    chatId.toString(),
                    style: textTheme.bodyLarge,
                  ),
                ),
              ),
            ],
            if (deleteError != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                deleteError!,
                style: TextStyle(color: scheme.error),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.link_off),
              label: const Text('Desconectar'),
              onPressed: isDeleting ? null : onDelete,
              style: FilledButton.styleFrom(
                backgroundColor: scheme.errorContainer,
                foregroundColor: scheme.onErrorContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
