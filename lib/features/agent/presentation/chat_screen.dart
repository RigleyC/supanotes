/// Agent chat screen backed by the app-owned agent controller and rendered
/// through `flutter_gen_ai_chat_ui`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/features/agent/presentation/controllers/chat_controller.dart';
import 'package:supanotes/features/agent/presentation/widgets/agent_chat_view.dart';
import 'package:supanotes/features/agent/presentation/widgets/new_session_button.dart';
import 'package:supanotes/shared/widgets/adaptive_sliver_nav_bar.dart';
import 'package:supanotes/shared/widgets/app_snackbar.dart';

class ChatScreen extends ConsumerWidget {
  const ChatScreen({super.key});

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

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const AdaptiveSliverNavBar(
            title: Text('Assistente'),
            actions: [NewSessionButton(), SizedBox(width: 8)],
          ),
          SliverFillRemaining(
            child: ref
                .watch(chatControllerProvider)
                .when(
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
                    onResolveConfirmation:
                        (confirmationId, {required approved}) => ref
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
          ),
        ],
      ),
    );
  }
}
