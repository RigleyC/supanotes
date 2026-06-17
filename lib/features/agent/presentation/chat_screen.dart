/// Agent chat screen backed by the app-owned agent controller and rendered
/// through `flutter_chat_ui`.
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

    final asyncState = ref.watch(chatControllerProvider);
    final state = asyncState.value;
    final messages = state?.messages ?? const [];
    final isStreaming = state?.isStreaming ?? false;
    final isLoaded = !asyncState.isLoading || messages.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat'),
        actions: const <Widget>[NewSessionButton()],
      ),
      body: SafeArea(
        top: false,
        child: AgentChatView(
          messages: messages,
          loaded: isLoaded,
          streaming: isStreaming,
          activeToolLabel: state?.activeToolLabel,
          errorMessage: state?.errorMessage,
          onRetry: state?.errorMessage == null || state?.retryMessage == null
              ? null
              : () => ref
                    .read(chatControllerProvider.notifier)
                    .retryLastMessage(),
          onCancel: isStreaming
              ? () =>
                    ref.read(chatControllerProvider.notifier).cancelStreaming()
              : null,
          onSend: (text) =>
              ref.read(chatControllerProvider.notifier).sendMessage(text),
        ),
      ),
    );
  }
}
