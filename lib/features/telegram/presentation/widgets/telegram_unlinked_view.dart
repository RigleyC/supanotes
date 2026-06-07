import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/features/telegram/presentation/controllers/telegram_link_controller.dart';
import 'package:supanotes/features/telegram/presentation/widgets/telegram_code_card.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';

class TelegramUnlinkedView extends ConsumerWidget {
  const TelegramUnlinkedView({super.key, required this.onGenerate});

  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(telegramLinkControllerProvider).asData?.value;
    final code = state?.code;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: AppSpacing.lg),
            const Icon(
              Icons.telegram_outlined,
              size: 72,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Conecte sua conta ao Telegram',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Receba e envie notas diretamente pelo chat do Telegram.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            if (code == null)
              FilledButton.icon(
                icon: const Icon(Icons.link),
                label: const Text('Conectar Telegram'),
                onPressed: state?.isLoading == true ? null : onGenerate,
              )
            else
              TelegramCodeCard(
                code: code,
                countdown: state?.countdown ?? 0,
                isExpired: (state?.countdown ?? 0) <= 0,
                onRegenerate: (state?.countdown ?? 0) <= 0
                    ? onGenerate
                    : null,
              ),
            if (state?.error != null && code == null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                state!.error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
