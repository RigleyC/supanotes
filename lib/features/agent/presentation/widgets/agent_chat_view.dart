import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart' as flyer;
import 'package:flutter_chat_ui/flutter_chat_ui.dart' as flyer_ui;

import 'package:supanotes/features/agent/domain/message_model.dart';
import 'package:supanotes/features/agent/presentation/chat_message_adapter.dart';
import 'package:supanotes/features/agent/presentation/widgets/chat_input.dart';
import 'package:supanotes/shared/widgets/empty_state.dart';

class AgentChatView extends StatefulWidget {
  const AgentChatView({
    super.key,
    required this.messages,
    required this.loaded,
    required this.streaming,
    required this.onSend,
  });

  final List<MessageModel> messages;
  final bool loaded;
  final bool streaming;
  final ValueChanged<String> onSend;

  @override
  State<AgentChatView> createState() => _AgentChatViewState();
}

class _AgentChatViewState extends State<AgentChatView> {
  late final flyer.InMemoryChatController _chatController;
  String _messageSignature = '';

  @override
  void initState() {
    super.initState();
    _chatController = flyer.InMemoryChatController();
    _scheduleMessageSync();
  }

  @override
  void didUpdateWidget(covariant AgentChatView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleMessageSync();
  }

  @override
  void dispose() {
    _chatController.dispose();
    super.dispose();
  }

  void _scheduleMessageSync() {
    final nextSignature = _signatureFor(widget.messages, widget.streaming);
    if (nextSignature == _messageSignature) return;
    _messageSignature = nextSignature;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final messages = toFlyerMessages(
        widget.messages,
        streaming: widget.streaming,
      );
      unawaited(_chatController.setMessages(messages));
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.loaded && widget.messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return flyer_ui.Chat(
      currentUserId: agentChatCurrentUserId,
      resolveUser: resolveAgentChatUser,
      chatController: _chatController,
      theme: flyer.ChatTheme.fromThemeData(Theme.of(context)),
      builders: flyer.Builders(
        emptyChatListBuilder: (_) => const EmptyState(
          icon: Icons.chat_bubble_outline,
          title: 'Comece uma conversa',
          subtitle: 'Pergunte algo ao agent e a resposta aparecer\u00e1 aqui.',
        ),
        customMessageBuilder: (context, message, index, {groupStatus, required isSentByMe}) {
          if (message.metadata?['kind'] == agentChatTypingKind) {
            return const Padding(
              key: ValueKey('agent-chat-typing-indicator'),
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: flyer_ui.IsTypingIndicator(),
              ),
            );
          }
          return const SizedBox.shrink();
        },
        composerBuilder: (_) => Align(
          alignment: Alignment.bottomCenter,
          child: ChatInput(
            enabled: !widget.streaming,
            onSend: widget.onSend,
          ),
        ),
      ),
      onMessageSend: widget.streaming ? null : widget.onSend,
    );
  }

  String _signatureFor(List<MessageModel> messages, bool streaming) {
    return [
      streaming ? 'streaming' : 'idle',
      for (final message in messages)
        '${message.id}:${message.role.name}:${message.content}',
    ].join('|');
  }
}
