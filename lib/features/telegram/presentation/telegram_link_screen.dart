import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:supanotes/core/api/api_exceptions.dart';
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
  bool _waitingForLink = false;
  bool _isDeleting = false;
  String? _deleteError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.listenManual(telegramLinkControllerProvider, (prev, next) {
        final prevLinked = prev?.asData?.value.linked ?? false;
        final nextLinked = next.asData?.value.linked ?? false;
        if (!prevLinked && nextLinked && _waitingForLink && mounted) {
          setState(() => _waitingForLink = false);
          AppMessenger.showSuccess(
            context,
            'Telegram conectado com sucesso!',
          );
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/home');
          }
        }
      });
    });
  }

  Future<void> _onGenerate() async {
    final controller = ref.read(telegramLinkControllerProvider.notifier);
    try {
      await controller.generateCode();
      if (mounted) setState(() => _waitingForLink = true);
    } on ApiException catch (e) {
      if (!mounted) return;
      AppMessenger.showError(context, e.message);
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

    setState(() {
      _deleteError = null;
      _isDeleting = true;
    });
    try {
      await ref.read(telegramLinkControllerProvider.notifier).deleteLink();
      if (!mounted) return;
      AppMessenger.showSuccess(context, 'Telegram desconectado');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _deleteError = e.message);
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stateAsync = ref.watch(telegramLinkControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Telegram')),
      body: stateAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => AppErrorView(
          title: err is ApiException ? err.message : err.toString(),
          onRetry: () => ref.invalidate(telegramLinkControllerProvider),
        ),
        data: (state) => state.linked
            ? TelegramLinkedView(
                username: state.username,
                chatId: state.chatId,
                onDelete: _onDelete,
                isDeleting: _isDeleting,
                deleteError: _deleteError,
              )
            : TelegramUnlinkedView(onGenerate: _onGenerate),
      ),
    );
  }
}
