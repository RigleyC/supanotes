import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:supanotes/core/api/api_exceptions.dart';
import 'package:supanotes/core/router/app_routes.dart';
import 'package:supanotes/features/telegram/data/telegram_repository.dart';
import 'package:supanotes/features/telegram/presentation/controllers/telegram_link_controller.dart';
import 'package:supanotes/features/telegram/presentation/widgets/telegram_linked_view.dart';
import 'package:supanotes/features/telegram/presentation/widgets/telegram_unlinked_view.dart';
import 'package:supanotes/shared/widgets/app_error_view.dart';
import 'package:supanotes/shared/widgets/app_snackbar.dart';
import 'package:supanotes/shared/widgets/confirm_dialog.dart';
class TelegramLinkScreen extends ConsumerStatefulWidget {
  const TelegramLinkScreen({super.key});

  @override
  ConsumerState<TelegramLinkScreen> createState() => _TelegramLinkScreenState();
}

class _TelegramLinkScreenState extends ConsumerState<TelegramLinkScreen> {
  @override
  Widget build(BuildContext context) {
    ref.listen(telegramStatusProvider, (prev, next) {
      final prevLinked = prev?.asData?.value.linked ?? false;
      final nextLinked = next.asData?.value.linked ?? false;
      final isPairing = ref.read(telegramPairingProvider).value != null;
      if (!prevLinked && nextLinked && isPairing && mounted) {
        AppMessenger.showSuccess('Telegram conectado com sucesso!');
        if (context.canPop()) {
          context.pop();
        } else {
          context.go(AppRoutes.home);
        }
      }
    });

    final statusAsync = ref.watch(telegramStatusProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Telegram')),
      body: statusAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => AppErrorView(
          title: err is ApiException ? err.message : err.toString(),
          onRetry: () => ref.invalidate(telegramStatusProvider),
        ),
        data: (status) => status.linked
            ? TelegramLinkedView(
                username: status.username,
                chatId: status.chatId,
                onDelete: _onDelete,
              )
            : TelegramUnlinkedView(onGenerate: _onGenerate),
      ),
    );
  }

  Future<void> _onGenerate() async {
    try {
      await ref.read(telegramPairingProvider.notifier).start();
    } on ApiException catch (e) {
      if (!mounted) return;
      AppMessenger.showError(e.message);
    }
  }

  Future<void> _onDelete() async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: 'Desconectar Telegram?',
      message:
          'Você deixará de receber mensagens no Telegram vinculado a esta conta.',
      confirmLabel: 'Desconectar',
      cancelLabel: 'Cancelar',
      destructive: true,
    );
    if (confirmed != true || !mounted) return;

    try {
      await ref.read(telegramRepositoryProvider).deleteLink();
      ref.invalidate(telegramStatusProvider);
      if (!mounted) return;
      AppMessenger.showSuccess('Telegram desconectado');
    } on ApiException catch (e) {
      if (!mounted) return;
      AppMessenger.showError(e.message);
    }
  }
}
