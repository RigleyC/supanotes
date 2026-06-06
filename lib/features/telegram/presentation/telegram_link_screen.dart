/// Telegram link flow screen.
///
/// Two distinct layouts depending on whether the user's account is
/// already linked to a Telegram chat:
///
///   * **Not linked** — big "Conectar Telegram" button. On tap we mint
///     a one-shot pairing code via [TelegramRepository.generateLinkCode]
///     and show it in a copyable card alongside a live countdown and
///     instructions for finishing the link inside Telegram. While the
///     code is on screen we poll [telegramLinkStatusProvider] every 5
///     seconds; the moment the backend reports the link is live we pop
///     back to the previous screen and surface a success snackbar.
///   * **Linked** — shows the linked `@username` in a card and a
///     "Desconectar" action that goes through a destructive
///     [showConfirmDialog] before calling
///     [TelegramRepository.deleteLink].
///
/// The screen owns two [Timer.periodic] instances (one for status
/// polling, one for the countdown). Both are cancelled in [dispose] so
/// the route can be torn down cleanly without leaving dangling ticks.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:supanotes/core/api/api_exceptions.dart';
import 'package:supanotes/features/telegram/data/telegram_repository.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/widgets/confirm_dialog.dart';

const String _kBotUsername = '@notes_agent_bot';
const Duration _kPollInterval = Duration(seconds: 5);
const Duration _kCountdownInterval = Duration(seconds: 1);

/// Current Telegram link status, auto-disposed when no longer watched.
final telegramLinkStatusProvider =
    FutureProvider.autoDispose<TelegramLinkStatus>((ref) async {
  final repo = ref.watch(telegramRepositoryProvider);
  return repo.getLinkStatus();
});

/// Holds the most recently generated pairing code, or `null` if the user
/// has not yet started a flow on this screen. Backed by an
/// [AsyncNotifier] so the loading / error states are first-class.
class TelegramLinkCodeController extends AsyncNotifier<TelegramLinkCode?> {
  @override
  Future<TelegramLinkCode?> build() async => null;

  /// Triggers a code mint. Throws on failure so the caller can surface
  /// the underlying [ApiException] message; the AsyncValue exposed via
  /// [telegramLinkCodeProvider] also reflects the loading / error state.
  Future<void> generate() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(telegramRepositoryProvider).generateLinkCode(),
    );
  }
}

final telegramLinkCodeProvider =
    AsyncNotifierProvider.autoDispose<TelegramLinkCodeController, TelegramLinkCode?>(
  TelegramLinkCodeController.new,
);

class TelegramLinkScreen extends ConsumerStatefulWidget {
  const TelegramLinkScreen({super.key});

  @override
  ConsumerState<TelegramLinkScreen> createState() => _TelegramLinkScreenState();
}

class _TelegramLinkScreenState extends ConsumerState<TelegramLinkScreen> {
  Timer? _pollTimer;
  Timer? _countdownTimer;

  /// True between a successful code mint and either a successful link or
  /// the user leaving the screen. We use this to decide whether a
  /// `linked: true` poll result should auto-pop or just refresh the UI.
  bool _waitingForLink = false;

  String? _deleteError;
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    _pollTimer = Timer.periodic(_kPollInterval, (_) {
      if (!mounted) return;
      ref.invalidate(telegramLinkStatusProvider);
    });
    // Ticking the countdown: cheap because the widget is small and the
    // child reads `code.remaining` lazily each rebuild.
    _countdownTimer = Timer.periodic(_kCountdownInterval, (_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _onGenerate() async {
    try {
      await ref.read(telegramLinkCodeProvider.notifier).generate();
      final code = ref.read(telegramLinkCodeProvider).asData?.value;
      if (code != null && mounted) {
        setState(() => _waitingForLink = true);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }
  }

  Future<void> _onDelete() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Desconectar Telegram?',
      message:
          'Você deixará de receber mensagens no Telegram vinculado a esta conta.',
      confirmLabel: 'Desconectar',
      cancelLabel: 'Cancelar',
      isDestructive: true,
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _deleteError = null;
      _isDeleting = true;
    });
    try {
      await ref.read(telegramRepositoryProvider).deleteLink();
      ref.invalidate(telegramLinkStatusProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Telegram desconectado')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _deleteError = e.message);
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  void _onStatusChanged(TelegramLinkStatus status) {
    if (!status.linked || !_waitingForLink) return;
    if (!mounted) return;
    setState(() => _waitingForLink = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Telegram conectado com sucesso!')),
    );
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<TelegramLinkStatus>>(
      telegramLinkStatusProvider,
      (_, next) => next.whenData(_onStatusChanged),
    );

    final statusAsync = ref.watch(telegramLinkStatusProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Telegram')),
      body: statusAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => _ErrorView(
          message: err is ApiException ? err.message : err.toString(),
          onRetry: () => ref.invalidate(telegramLinkStatusProvider),
        ),
        data: (status) => status.linked
            ? _LinkedView(
                status: status,
                onDelete: _onDelete,
                isDeleting: _isDeleting,
                deleteError: _deleteError,
              )
            : _UnlinkedView(onGenerate: _onGenerate),
      ),
    );
  }
}

class _UnlinkedView extends ConsumerWidget {
  const _UnlinkedView({required this.onGenerate});

  final Future<void> Function() onGenerate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final codeAsync = ref.watch(telegramLinkCodeProvider);
    final code = codeAsync.asData?.value;

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
                onPressed: codeAsync.isLoading ? null : onGenerate,
              )
            else
              _CodeCard(
                code: code,
                onCopy: () => _onCopy(context, code.code),
                onRegenerate: code.isExpired
                    ? onGenerate
                    : null,
              ),
            if (codeAsync.hasError) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                codeAsync.error is ApiException
                    ? (codeAsync.error as ApiException).message
                    : codeAsync.error.toString(),
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

  Future<void> _onCopy(BuildContext context, String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Código copiado')),
    );
  }
}

class _CodeCard extends StatelessWidget {
  const _CodeCard({
    required this.code,
    required this.onCopy,
    this.onRegenerate,
  });

  final TelegramLinkCode code;
  final VoidCallback onCopy;
  final VoidCallback? onRegenerate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final remaining = code.remaining;
    final mm = remaining.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = remaining.inSeconds.remainder(60).toString().padLeft(2, '0');

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
              code.code,
              textAlign: TextAlign.center,
              style: textTheme.headlineMedium?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              code.isExpired
                  ? 'Código expirado'
                  : 'Expira em $mm:$ss',
              textAlign: TextAlign.center,
              style: textTheme.bodySmall?.copyWith(
                color: code.isExpired ? scheme.error : scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.copy_outlined, size: 18),
                  label: const Text('Copiar'),
                  onPressed: onCopy,
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
              '/start ${code.code}',
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
}

class _LinkedView extends StatelessWidget {
  const _LinkedView({
    required this.status,
    required this.onDelete,
    required this.isDeleting,
    required this.deleteError,
  });

  final TelegramLinkStatus status;
  final VoidCallback onDelete;
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
                  status.username ?? '(sem username)',
                  style: textTheme.bodyLarge,
                ),
              ),
            ),
            if (status.chatId != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.tag),
                  title: const Text('Chat ID'),
                  subtitle: Text(
                    status.chatId.toString(),
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

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: AppSpacing.md),
            Text(
              message,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton(
              onPressed: onRetry,
              child: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }
}
