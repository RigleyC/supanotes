/// Agent chat screen — request/response loop (no SSE).
///
/// The screen renders an in-memory chat history that the [ChatController]
/// pulls from `GET /api/v1/agent/messages` on open and on session
/// rotation, and augments with optimistic user messages and the
/// assistant's reply returned by `POST /api/v1/agent/chat`. While the
/// request is in flight a [TypingIndicator] is appended below the last
/// bubble so the user knows the agent is composing.
///
/// Lives next to the existing `agent_repository.dart` (used by the FE-5
/// inbox-organize sheet) and reuses the same [ApiClient] / DI graph.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/widgets/app_snackbar.dart';
import 'package:supanotes/shared/widgets/empty_state.dart';

import 'controllers/chat_controller.dart';
import 'widgets/chat_input.dart';
import 'widgets/message_bubble.dart';
import 'widgets/new_session_button.dart';
import 'widgets/typing_indicator.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<ChatState>(chatControllerProvider, (prev, next) {
      final messageCountChanged = prev?.messages.length != next.messages.length;
      final streamingChanged = prev?.streaming != next.streaming;
      if (messageCountChanged || streamingChanged) {
        _scrollToBottom();
      }
      if (next.error != null && next.error != prev?.error) {
        AppMessenger.showError(context, next.error!);
      }
    });

    final state = ref.watch(chatControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat'),
        actions: const <Widget>[NewSessionButton()],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            Expanded(
              child: _buildBody(state),
            ),
            ChatInput(
              enabled: !state.streaming,
              onSend: (text) =>
                  ref.read(chatControllerProvider.notifier).sendMessage(text),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ChatState state) {
    if (state.messages.isEmpty && state.loaded) {
      return const EmptyState(
        icon: Icons.chat_bubble_outline,
        title: 'Comece uma conversa',
        subtitle: 'Pergunte algo ao agent e a resposta aparecerá aqui.',
      );
    }
    if (state.messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      itemCount: state.messages.length + (state.streaming ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == state.messages.length) {
          return const TypingIndicator();
        }
        return MessageBubble(message: state.messages[index]);
      },
    );
  }
}
