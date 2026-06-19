import 'package:flutter/material.dart';
import 'package:flutter_gen_ai_chat_ui/flutter_gen_ai_chat_ui.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart' show MarkdownStyleSheet;

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

    final theme = Theme.of(context);

    final bubbleStyle = BubbleStyle(
      enableShadow: false,
      userBubbleColor: Colors.transparent,
      aiBubbleColor: Colors.transparent,
      userBubbleMaxWidth: double.infinity,
      aiBubbleMaxWidth: double.infinity,
      userBubbleTopLeftRadius: 0,
      userBubbleTopRightRadius: 0,
      aiBubbleTopLeftRadius: 0,
      aiBubbleTopRightRadius: 0,
      bottomLeftRadius: 0,
      bottomRightRadius: 0,
    );

    final options = MessageOptions(
      showTime: false,
      showCopyButton: true,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      containerColor: theme.colorScheme.surfaceContainerLow,
      bubbleStyle: bubbleStyle,
    );

    final inputOpts = InputOptions(
      decoration: InputDecoration(
        hintText: 'Mensagem...',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide(color: theme.colorScheme.outline),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
      ),
      sendButtonBuilder: (onSend) => IconButton(
        icon: const Icon(Icons.arrow_upward),
        style: IconButton.styleFrom(
          backgroundColor: theme.colorScheme.primary,
          foregroundColor: theme.colorScheme.onPrimary,
        ),
        onPressed: onSend,
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
            streamingWordByWord: true,
            streamingFadeInEnabled: true,
            streamingFadeInDuration: const Duration(milliseconds: 150),
            loadingConfig: LoadingConfig(isLoading: widget.streaming),
            maxWidth: 768,
            resultRenderers: {
              'confirmation': _buildConfirmationCard,
              'action': _buildActionCard,
            },
            welcomeMessageConfig: WelcomeMessageConfig(
              title: 'Como posso ajudar?',
              centerVertically: true,
            ),
            exampleQuestions: const [
              ExampleQuestion(question: 'Resumir minhas notas'),
              ExampleQuestion(question: 'O que tenho para fazer hoje?'),
              ExampleQuestion(question: 'Criar uma tarefa'),
            ],
            markdownStyleSheet: MarkdownStyleSheet(
              codeblockDecoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
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

  Widget _buildActionCard(BuildContext context, Map<String, dynamic> data) {
    final statusName = data['status'] as String? ?? 'running';
    final label = data['label'] as String? ?? 'Executando...';
    final message = data['message'] as String?;
    
    final status = ChatToolActionStatus.values.firstWhere(
      (e) => e.name == statusName,
      orElse: () => ChatToolActionStatus.running,
    );

    return _AgentActionCard(
      key: ValueKey('action-${data['actionId']}'),
      status: status,
      label: label,
      message: message,
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

class _AgentActionCard extends StatelessWidget {
  const _AgentActionCard({
    super.key,
    required this.status,
    required this.label,
    this.message,
  });

  final ChatToolActionStatus status;
  final String label;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    Widget icon;
    Color? textColor;
    
    switch (status) {
      case ChatToolActionStatus.running:
        icon = const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
        break;
      case ChatToolActionStatus.completed:
      case ChatToolActionStatus.confirmed:
        icon = Icon(Icons.check_circle, size: 16, color: theme.colorScheme.primary);
        break;
      case ChatToolActionStatus.failed:
      case ChatToolActionStatus.cancelled:
        icon = Icon(Icons.error, size: 16, color: theme.colorScheme.error);
        textColor = theme.colorScheme.error;
        break;
      case ChatToolActionStatus.confirmationRequired:
        icon = Icon(Icons.warning, size: 16, color: theme.colorScheme.primary);
        break;
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              icon,
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: textColor ?? theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          if (message != null && message!.isNotEmpty && status == ChatToolActionStatus.failed) ...[
            const SizedBox(height: 4),
            Text(
              message!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ]
        ],
      ),
    );
  }
}
