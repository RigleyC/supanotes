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
    required this.activeToolLabel,
    required this.errorMessage,
    this.onRetry,
    this.onCancel,
  });

  final List<MessageModel> messages;
  final bool loaded;
  final bool streaming;
  final ValueChanged<String> onSend;
  final String? activeToolLabel;
  final String? errorMessage;
  final VoidCallback? onRetry;
  final VoidCallback? onCancel;

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

    final chat = flyer_ui.Chat(
      currentUserId: agentChatCurrentUserId,
      resolveUser: resolveAgentChatUser,
      chatController: _chatController,
      theme: flyer.ChatTheme.fromThemeData(Theme.of(context)),
      builders: flyer.Builders(
        emptyChatListBuilder: (_) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const EmptyState(
              icon: Icons.chat_bubble_outline,
              title: 'Comece uma conversa',
              subtitle: 'Pergunte algo ao agente e a resposta aparecer\u00e1 aqui.',
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              alignment: WrapAlignment.center,
              children: [
                ActionChip(
                  label: const Text('Resuma minhas notas recentes'),
                  onPressed: () => widget.onSend('Resuma minhas notas recentes'),
                ),
                ActionChip(
                  label: const Text('Quais tarefas vencem hoje?'),
                  onPressed: () => widget.onSend('Quais tarefas vencem hoje?'),
                ),
                ActionChip(
                  label: const Text('Organize meu inbox'),
                  onPressed: () => widget.onSend('Organize meu inbox'),
                ),
              ],
            ),
          ],
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

    final statusBar = _AgentChatStatusBar(
      activeToolLabel: widget.activeToolLabel,
      errorMessage: widget.errorMessage,
      onRetry: widget.onRetry,
      onCancel: widget.onCancel,
    );

    if (statusBar.isHidden) return chat;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: chat),
        statusBar,
      ],
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

class _AgentChatStatusBar extends StatelessWidget {
  const _AgentChatStatusBar({
    this.activeToolLabel,
    this.errorMessage,
    this.onRetry,
    this.onCancel,
  });

  final String? activeToolLabel;
  final String? errorMessage;
  final VoidCallback? onRetry;
  final VoidCallback? onCancel;

  bool get isHidden =>
      activeToolLabel == null && errorMessage == null && onRetry == null && onCancel == null;

  @override
  Widget build(BuildContext context) {

    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: theme.colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          if (activeToolLabel != null) ...[
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                activeToolLabel!,
                style: theme.textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          if (errorMessage != null) ...[
            Icon(Icons.error_outline, size: 16, color: theme.colorScheme.error),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                errorMessage!,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              child: const Text('Tentar novamente'),
            ),
          const Spacer(),
          if (onCancel != null)
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              tooltip: 'Cancelar resposta',
              onPressed: onCancel,
            ),
        ],
      ),
    );
  }
}
