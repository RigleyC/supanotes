import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/widgets/app_snackbar.dart';

const String _kBotUsername = '@notes_agent_bot';

class TelegramCodeCard extends StatelessWidget {
  const TelegramCodeCard({
    super.key,
    required this.code,
    required this.countdown,
    required this.isExpired,
    this.onRegenerate,
  });

  final String code;
  final int countdown;
  final bool isExpired;
  final VoidCallback? onRegenerate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final mm = (countdown ~/ 60).toString().padLeft(2, '0');
    final ss = (countdown % 60).toString().padLeft(2, '0');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Seu código de pareamento',
              style: textTheme.labelLarge?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            SelectableText(
              code,
              textAlign: TextAlign.center,
              style: textTheme.headlineMedium?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              isExpired
                  ? 'Código expirado'
                  : 'Expira em $mm:$ss',
              textAlign: TextAlign.center,
              style: textTheme.bodySmall?.copyWith(
                color: isExpired ? scheme.error : scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.copy_outlined, size: 18),
                  label: const Text('Copiar'),
                  onPressed: () => _onCopy(context),
                ),
                if (onRegenerate != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Gerar novo'),
                    onPressed: onRegenerate,
                  ),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: Text.rich(
                TextSpan(
                  text: 'Abra ',
                  style: textTheme.bodyMedium,
                  children: [
                    TextSpan(
                      text: _kBotUsername,
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const TextSpan(text: ' no Telegram e envie:'),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '/start $code',
              textAlign: TextAlign.center,
              style: textTheme.bodyLarge?.copyWith(
                fontFamily: 'monospace',
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'A vinculação acontece automaticamente assim que você enviar o comando. '
              'Esta tela atualiza sozinha.',
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _onCopy(BuildContext context) {
    Clipboard.setData(ClipboardData(text: code));
    AppMessenger.showInfo(context, 'Código copiado');
  }
}
