/// Agent chat screen backed by the app-owned agent controller and rendered
/// through `flutter_gen_ai_chat_ui`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/features/agent/presentation/controllers/chat_controller.dart';
import 'package:supanotes/features/agent/presentation/widgets/agent_chat_view.dart';
import 'package:supanotes/shared/widgets/app_snackbar.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:supanotes/shared/widgets/confirm_dialog.dart';
import 'package:supanotes/features/agent/data/chat_repository.dart';
import 'package:supanotes/features/agent/domain/session_manager.dart';

class ChatScreen extends ConsumerWidget {
  const ChatScreen({super.key});

  Future<void> _handleNewSession(BuildContext context, WidgetRef ref) async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: 'Nova conversa',
      message: 'Iniciar uma nova conversa? O histórico atual será apagado.',
      confirmLabel: 'Nova conversa',
      destructive: true,
    );
    if (confirmed != true) return;

    final oldSessionId = ref.read(sessionManagerProvider);
    try {
      await ref.read(chatRepositoryProvider).clearHistory(oldSessionId);
    } catch (e) {
      debugPrint('new session error: $e');
      AppMessenger.showError('Não foi possível limpar o histórico no servidor.');
    }
    ref.read(sessionManagerProvider.notifier).newSession();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<AsyncValue<ChatState>>(chatControllerProvider, (prev, next) {
      next.whenOrNull(
        error: (err, _) {
          if (err.toString() != prev?.error?.toString()) {
            AppMessenger.showError(err.toString());
          }
        },
      );
    });

    void onSend(String text) =>
        ref.read(chatControllerProvider.notifier).sendMessage(text);

    return AdaptiveScaffold(
      appBar: AdaptiveAppBar(
        title: 'Assistente',
        actions: [
          AdaptiveAppBarAction(
            icon: Icons.add_comment_outlined,
            iosSymbol: 'plus.bubble',
            onPressed: () => _handleNewSession(context, ref),
          ),
        ],
      ),
      body: ref.watch(chatControllerProvider).when(
            skipError: true,
            data: (state) => AgentChatView(
              messages: state.messages,
              actions: state.actions,
              loaded: true,
              streaming: state.isStreaming,
              loadingLabel: state.loadingLabel,
              onCancel: state.isStreaming
                  ? () => ref
                        .read(chatControllerProvider.notifier)
                        .cancelStreaming()
                  : null,
              onSend: onSend,
              onResolveConfirmation: (confirmationId, {required approved}) =>
                  ref
                      .read(chatControllerProvider.notifier)
                      .resolveToolConfirmation(
                        confirmationId,
                        approved: approved,
                      ),
            ),
            loading: () => AgentChatView(
              messages: const [],
              actions: const [],
              loaded: false,
              streaming: false,
              onSend: onSend,
            ),
            error: (err, _) => AgentChatView(
              messages: const [],
              actions: const [],
              loaded: true,
              streaming: false,
              onSend: onSend,
            ),
          ),
    );
  }
}
