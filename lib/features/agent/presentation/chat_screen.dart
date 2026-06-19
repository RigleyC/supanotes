/// Agent chat screen backed by the app-owned agent controller and rendered
/// through `flutter_gen_ai_chat_ui`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/features/agent/presentation/controllers/chat_controller.dart';
import 'package:supanotes/features/agent/presentation/widgets/agent_chat_view.dart';
import 'package:supanotes/features/agent/presentation/widgets/new_session_button.dart';
import 'package:supanotes/shared/widgets/app_snackbar.dart';

class ChatScreen extends ConsumerWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<AsyncValue<ChatState>>(chatControllerProvider, (prev, next) {
      if (!next.isLoading && next.hasError && next.error != prev?.error) {
        AppMessenger.showError(context, next.error.toString());
      }
    });

    void onSend(String text) =>
        ref.read(chatControllerProvider.notifier).sendMessage(text);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const SliverAppBar.medium(
            title: Text('Assistente'),
            actions: [
              NewSessionButton(),
              SizedBox(width: 8),
            ],
          ),
          SliverFillRemaining(
            child: ref.watch(chatControllerProvider).when(
                  data: (state) => AgentChatView(
                    messages: state.messages,
                    actions: state.actions,
                    loaded: true,
                    streaming: state.isStreaming,
                    errorMessage: state.errorMessage,
                    onRetry: state.retryMessage != null
                        ? () => ref
                            .read(chatControllerProvider.notifier)
                            .retryLastMessage()
                        : null,
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
                    errorMessage: null,
                    onSend: onSend,
                  ),
                  error: (err, _) => AgentChatView(
                    messages: const [],
                    actions: const [],
                    loaded: true,
                    streaming: false,
                    errorMessage: err.toString(),
                    onSend: onSend,
                  ),
                ),
          ),
        ],
      ),
    );
  }
}
