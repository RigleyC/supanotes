import 'package:flutter/material.dart';
import 'package:flutter_gen_ai_chat_ui/flutter_gen_ai_chat_ui.dart';

import 'package:supanotes/features/agent/domain/message_model.dart';
import 'package:supanotes/features/agent/presentation/chat_message_adapter.dart';
import 'package:supanotes/features/agent/presentation/controllers/chat_controller.dart';
import 'package:supanotes/shared/widgets/app_button.dart';


class AgentChatView extends StatefulWidget {
  const AgentChatView({
    super.key,
    required this.messages,
    required this.actions,
    required this.loaded,
    required this.streaming,
    required this.onSend,
    required this.errorMessage,
    this.onRetry,
    this.onCancel,
    this.onResolveConfirmation,
  });

  final List<MessageModel> messages;
  final List<ChatToolAction> actions;
  final bool loaded;
  final bool streaming;
  final ValueChanged<String> onSend;
  final String? errorMessage;
  final VoidCallback? onRetry;
  final VoidCallback? onCancel;
  final void Function(String confirmationId, {required bool approved})?
      onResolveConfirmation;

  @override
  State<AgentChatView> createState() => _AgentChatViewState();
}

class _AgentChatViewState extends State<AgentChatView> {
  late final ChatMessagesController _controller;
  String _lastSignature = '';

  @override
  void initState() {
    super.initState();
    _controller = ChatMessagesController();
    _syncMessages();
  }

  @override
  void didUpdateWidget(covariant AgentChatView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncMessages();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _syncMessages() {
    final nextSignature = _buildSignature();
    if (nextSignature == _lastSignature) return;
    _lastSignature = nextSignature;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final genAiMessages = toGenAiChatMessages(
        widget.messages,
        actions: widget.actions,
      );
      _controller.setMessages(genAiMessages);
    });
  }

  String _buildSignature() {
    final lastContent = widget.messages.isNotEmpty
        ? widget.messages.last.content
        : '';
    return '${widget.messages.length}:${widget.actions.length}:${widget.streaming}:${lastContent.length}';
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.loaded && widget.messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final options = MessageOptions(
      showTime: false,
      showCopyButton: false,
    );

    final inputOpts = InputOptions(
      decoration: const InputDecoration(
        hintText: 'Mensagem...',
        border: InputBorder.none,
      ),
    );

    return Column(
      children: [
        Expanded(
          child: AiChatWidget(
            currentUser: agentChatCurrentUser,
            aiUser: agentChatAssistantUser,
            controller: _controller,
            onSendMessage: (message) => widget.onSend(message.text),
            onCancelGenerating: widget.onCancel,
            messageOptions: options,
            inputOptions: inputOpts,
            enableMarkdownStreaming: true,
            loadingConfig: LoadingConfig(isLoading: widget.streaming),
            resultRenderers: {
              'confirmation': _buildConfirmationCard,
            },
          ),
        ),
        if (widget.errorMessage != null)
          _ErrorBanner(
            message: widget.errorMessage!,
            onRetry: widget.onRetry,
          ),
      ],
    );
  }

  Widget _buildConfirmationCard(BuildContext context, Map<String, dynamic> data) {
    final confirmationId = data['confirmationId'] as String? ?? '';
    final label = data['label'] as String? ?? '';

    return _ConfirmationCard(
      key: ValueKey('confirm-$confirmationId'),
      label: label,
      onApprove: () =>
          widget.onResolveConfirmation?.call(confirmationId, approved: true),
      onCancel: () =>
          widget.onResolveConfirmation?.call(confirmationId, approved: false),
    );
  }
}

class _ConfirmationCard extends StatelessWidget {
  const _ConfirmationCard({
    super.key,
    required this.label,
    required this.onApprove,
    required this.onCancel,
  });

  final String label;
  final VoidCallback onApprove;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Confirmação necessária',
                  style: theme.textTheme.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(label, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                AppButton(
                  text: 'Cancelar',
                  onPressed: onCancel,
                  variant: AppButtonVariant.secondary,
                  width: 100,
                ),
                const SizedBox(width: 8),
                AppButton(
                  text: 'Confirmar',
                  onPressed: onApprove,
                  variant: AppButtonVariant.primary,
                  width: 100,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({
    required this.message,
    this.onRetry,
  });

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: theme.colorScheme.errorContainer,
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 16, color: theme.colorScheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
          if (onRetry != null)
            AppButton(
              text: 'Tentar novamente',
              onPressed: onRetry,
              variant: AppButtonVariant.tonal,
              width: 140,
            ),
        ],
      ),
    );
  }
}
