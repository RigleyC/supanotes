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
    final pairingAsync = ref.watch(telegramPairingProvider);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: AppSpacing.lg),
            const Icon(Icons.telegram_outlined, size: 72),
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
            pairingAsync.when(
              data: (pairing) {
                if (pairing == null) {
                  return FilledButton.icon(
                    icon: const Icon(Icons.link),
                    label: const Text('Conectar Telegram'),
                    onPressed: onGenerate,
                  );
                }
                return TelegramCodeCard(
                  code: pairing.code,
                  countdown: pairing.countdown,
                  isExpired: pairing.countdown <= 0,
                  onRegenerate: pairing.countdown <= 0 ? onGenerate : null,
                );
              },
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.md),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (err, _) => Column(
                children: [
                  Text(
                    'Erro: $err',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  FilledButton.icon(
                    icon: const Icon(Icons.refresh),
                    label: const Text('Tentar novamente'),
                    onPressed: onGenerate,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
