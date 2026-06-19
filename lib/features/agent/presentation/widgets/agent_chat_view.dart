import 'package:flutter/material.dart';
import 'package:flutter_gen_ai_chat_ui/flutter_gen_ai_chat_ui.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart' show MarkdownBody, MarkdownStyleSheet;
import 'package:url_launcher/url_launcher.dart';

import 'package:supanotes/features/agent/domain/agent_strings.dart';
import 'package:supanotes/features/agent/domain/message_model.dart';
import 'package:supanotes/features/agent/presentation/chat_message_adapter.dart';
import 'package:supanotes/features/agent/presentation/controllers/chat_controller.dart';
import 'package:supanotes/features/agent/presentation/widgets/agent_action_card.dart';
import 'package:supanotes/features/agent/presentation/widgets/confirmation_card.dart';
import 'package:supanotes/features/agent/presentation/widgets/collapsible_thinking_card.dart';


class AgentChatView extends StatefulWidget {
  const AgentChatView({
    super.key,
    required this.messages,
    required this.actions,
    required this.loaded,
    required this.streaming,
    required this.onSend,
    this.onCancel,
    this.onResolveConfirmation,
  });

  final List<MessageModel> messages;
  final List<ChatToolAction> actions;
  final bool loaded;
  final bool streaming;
  final ValueChanged<String> onSend;
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
    final isDark = theme.brightness == Brightness.dark;

    final bubbleStyle = BubbleStyle(
      enableShadow: false,
      userBubbleColor: theme.colorScheme.primaryContainer,
      aiBubbleColor: Colors.transparent,
      userBubbleMaxWidth: MediaQuery.of(context).size.width * 0.75,
      aiBubbleMaxWidth: MediaQuery.of(context).size.width * 0.85,
      userBubbleTopLeftRadius: 16,
      userBubbleTopRightRadius: 16,
      aiBubbleTopLeftRadius: 0,
      aiBubbleTopRightRadius: 0,
      bottomLeftRadius: 16,
      bottomRightRadius: 16,
    );

    final effectiveStyleSheet = MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: theme.textTheme.bodyMedium?.copyWith(fontSize: 16),
      listBullet: theme.textTheme.bodyMedium?.copyWith(fontSize: 16),
      strong: theme.textTheme.bodyMedium?.copyWith(fontSize: 16, fontWeight: FontWeight.bold),
      em: theme.textTheme.bodyMedium?.copyWith(fontSize: 16, fontStyle: FontStyle.italic),
      code: theme.textTheme.bodyMedium?.copyWith(
        fontFamily: 'monospace',
        fontSize: 14,
        color: theme.colorScheme.onSurfaceVariant,
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
      ),
      codeblockPadding: const EdgeInsets.all(12),
      codeblockDecoration: BoxDecoration(
        color: isDark ? const Color(0xFF15151F) : const Color(0xFFF4F4F8),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outlineVariant,
        ),
      ),
    );

    final options = MessageOptions(
      showTime: false,
      showCopyButton: true,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      containerColor: Colors.transparent,
      bubbleStyle: bubbleStyle,
      userTextColor: theme.colorScheme.onPrimaryContainer,
      aiTextColor: theme.colorScheme.onSurface,
      textStyle: theme.textTheme.bodyMedium?.copyWith(fontSize: 16),
      markdownStyleSheet: effectiveStyleSheet,
      markdownBuilder: (context, text, stylesheet, isUser) {
        final thinkingRegex = RegExp(r'<thinking>([\s\S]*?)(?:</thinking>|$)');
        final match = thinkingRegex.firstMatch(text);

        Widget? thinkingWidget;
        String markdownText = text;

        if (match != null) {
          final thinkingText = match.group(1)?.trim() ?? '';
          markdownText = text.replaceFirst(match.group(0)!, '').trim();
          final isFinished = text.contains('</thinking>');

          thinkingWidget = CollapsibleThinkingCard(
            thinkingText: thinkingText,
            isFinished: isFinished,
          );
        }

        Future<void> handleTapLink(String? href) async {
          if (href != null) {
            final uri = Uri.tryParse(href);
            if (uri != null && await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          }
        }

        final markdownBody = markdownText.isNotEmpty
            ? MarkdownBody(
                data: markdownText,
                styleSheet: stylesheet,
                onTapLink: (text, href, title) => handleTapLink(href),
              )
            : const SizedBox.shrink();

        if (thinkingWidget != null) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              thinkingWidget,
              markdownBody,
            ],
          );
        }

        return markdownBody;
      },
    );

    final inputOpts = InputOptions(
      decoration: InputDecoration(
        hintText: AgentStrings.inputHint,
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
              title: AgentStrings.welcomeTitle,
              centerVertically: true,
            ),
            exampleQuestions: AgentStrings.exampleQuestions
                .map((q) => ExampleQuestion(question: q))
                .toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildConfirmationCard(BuildContext context, Map<String, dynamic> data) {
    final confirmationId = data['confirmationId'] as String? ?? '';
    final label = data['label'] as String? ?? '';

    return ConfirmationCard(
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
    final label = data['label'] as String? ?? AgentStrings.actionDefaultLabel;
    final message = data['message'] as String?;
    
    final status = ChatToolActionStatus.values.firstWhere(
      (e) => e.name == statusName,
      orElse: () => ChatToolActionStatus.running,
    );

    return AgentActionCard(
      key: ValueKey('action-${data['actionId']}'),
      status: status,
      label: label,
      message: message,
    );
  }
}
