import 'package:flutter/material.dart';
import 'package:flutter_gen_ai_chat_ui/flutter_gen_ai_chat_ui.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart' show MarkdownBody, MarkdownStyleSheet;
import 'package:flutter_streaming_text_markdown/flutter_streaming_text_markdown.dart' show StreamingText;
import 'package:url_launcher/url_launcher.dart';

import 'package:supanotes/features/agent/domain/agent_strings.dart';
import 'package:supanotes/features/agent/domain/message_model.dart';
import 'package:supanotes/features/agent/presentation/chat_message_adapter.dart';
import 'package:supanotes/features/agent/presentation/controllers/chat_controller.dart';
import 'package:supanotes/features/agent/presentation/widgets/agent_action_timeline_card.dart';
import 'package:supanotes/features/agent/presentation/widgets/collapsible_thinking_card.dart';
import 'package:supanotes/features/agent/presentation/widgets/shimmer_text.dart';


class AgentChatView extends StatefulWidget {
  const AgentChatView({
    super.key,
    required this.messages,
    required this.actions,
    required this.loaded,
    required this.streaming,
    required this.onSend,
    this.loadingLabel,
    this.onCancel,
    this.onResolveConfirmation,
  });

  final List<MessageModel> messages;
  final List<ChatToolAction> actions;
  final bool loaded;
  final bool streaming;
  final String? loadingLabel;
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
    final oldSignature = _lastSignature;
    _lastSignature = nextSignature;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final genAiMessages = toGenAiChatMessages(
        widget.messages,
        actions: widget.actions,
      );
      _controller.setMessages(genAiMessages);

      // Manage streaming message state in the controller
      if (widget.streaming && widget.messages.isNotEmpty) {
        final lastAssistantIndex = widget.messages.lastIndexWhere(
          (m) => m.role == MessageRole.assistant,
        );
        if (lastAssistantIndex != -1) {
          final lastAssistant = widget.messages[lastAssistantIndex];
          _controller.setStreamingMessage(lastAssistant.id);
        }
      } else {
        _controller.setStreamingMessage(null);
      }

      // Scroll to bottom if:
      // 1. Number of messages changed
      // 2. Number of actions changed
      // 3. We are currently streaming (on every token/content length change)
      final oldParts = oldSignature.split(':');
      final newParts = nextSignature.split(':');
      final msgCountChanged = oldParts.isEmpty || oldParts[0] != newParts[0];
      final actionsCountChanged = oldParts.length < 2 || oldParts[1] != newParts[1];
      final isStreaming = widget.streaming;

      if (msgCountChanged || actionsCountChanged || isStreaming) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          try {
            _controller.scrollToBottom();
          } catch (e) {
            debugPrint('Scroll to bottom failed: $e');
          }
        });
      }
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
      userBubbleColor: isDark ? const Color(0xFF2F2F2F) : const Color(0xFFF4F4F4),
      aiBubbleColor: Colors.transparent,
      userBubbleMaxWidth: MediaQuery.of(context).size.width * 0.85,
      aiBubbleMaxWidth: MediaQuery.of(context).size.width,
      userBubbleTopLeftRadius: 20,
      userBubbleTopRightRadius: 20,
      aiBubbleTopLeftRadius: 0,
      aiBubbleTopRightRadius: 0,
      bottomLeftRadius: 20,
      bottomRightRadius: 20,
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
      showUserName: false,
      showTime: false,
      showCopyButton: true,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      containerMargin: EdgeInsets.zero,
      decoration: const BoxDecoration(
        color: Colors.transparent,
        border: Border(),
      ),
      bubbleStyle: bubbleStyle,
      userTextColor: theme.colorScheme.onPrimaryContainer,
      aiTextColor: theme.colorScheme.onSurface,
      textStyle: theme.textTheme.bodyMedium?.copyWith(fontSize: 16),
      markdownStyleSheet: effectiveStyleSheet,
      markdownBuilder: (context, text, stylesheet, isUser) {
        final thinkingRegex = RegExp(r'<(?:think|thinking)>([\s\S]*?)(?:</(?:think|thinking)>|$)');
        final match = thinkingRegex.firstMatch(text);

        Widget? thinkingWidget;
        String markdownText = text;

        if (match != null) {
          final thinkingText = match.group(1)?.trim() ?? '';
          markdownText = text.replaceFirst(match.group(0)!, '').trim();
          final isFinished = text.contains('</thinking>') || text.contains('</think>');

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

        final isStreamingMessage = widget.streaming && !isUser && 
            widget.messages.isNotEmpty &&
            widget.messages.last.role == MessageRole.assistant &&
            widget.messages.last.content == text;

        final markdownBody = markdownText.isNotEmpty
            ? (isStreamingMessage
                ? StreamingText(
                    text: markdownText,
                    style: stylesheet.p,
                    typingSpeed: const Duration(milliseconds: 30),
                    markdownEnabled: true,
                    fadeInEnabled: true,
                    fadeInDuration: const Duration(milliseconds: 150),
                    wordByWord: true,
                    showCursor: false,
                  )
                : MarkdownBody(
                    data: markdownText,
                    styleSheet: stylesheet,
                    onTapLink: (text, href, title) => handleTapLink(href),
                  ))
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
        filled: true,
        fillColor: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF0F0F0),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(32),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(32),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(32),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 14,
        ),
      ),
      sendButtonBuilder: (onSend) => Container(
        margin: const EdgeInsets.only(left: 12, right: 8),
        decoration: const BoxDecoration(
          color: Colors.blue,
          shape: BoxShape.circle,
        ),
        child: IconButton(
          icon: const Icon(Icons.arrow_upward, color: Colors.white, size: 20),
          onPressed: onSend,
        ),
      ),
    );

    final spacingConfig = ChatSpacingConfig(
      messageListPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      messageBubbleMargin: (isUser) {
        if (isUser) {
          return const EdgeInsets.only(
            top: 6.0,
            bottom: 6.0,
            left: 48.0,
            right: 0.0,
          );
        } else {
          return const EdgeInsets.only(
            top: 6.0,
            bottom: 6.0,
            left: 0.0,
            right: 0.0,
          );
        }
      },
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
            spacingConfig: spacingConfig,
            inputOptions: inputOpts,
            enableMarkdownStreaming: true,
            streamingWordByWord: true,
            streamingFadeInEnabled: true,
            streamingFadeInDuration: const Duration(milliseconds: 150),
            loadingConfig: LoadingConfig(
              isLoading: widget.streaming,
              loadingIndicator: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ShimmerText(
                      child: Text(
                        widget.loadingLabel ?? 'Pensando...',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            maxWidth: 768,
            resultRenderers: {
              'action_timeline': _buildActionTimelineCard,
            },
            welcomeMessageConfig: WelcomeMessageConfig(
              containerDecoration: const BoxDecoration(color: Colors.transparent),
              containerPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              builder: () => _buildEmptyStateList(context),
              centerVertically: true,
            ),
            exampleQuestions: const [],
          ),
        ),
      ],
    );
  }

  Widget _buildActionTimelineCard(BuildContext context, Map<String, dynamic> data) {
    final actions = data['actions'] as List<ChatToolAction>;
    return AgentActionTimelineCard(
      actions: actions,
      onResolveConfirmation: widget.onResolveConfirmation,
    );
  }

  Widget _buildEmptyStateList(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildEmptyStateItem(context, Icons.edit_document, 'Resumir minhas notas', () {
          widget.onSend('Resuma minhas notas');
        }),
        const SizedBox(height: 12),
        _buildEmptyStateItem(context, Icons.search, 'Procurar por ideias sobre...', () {
          widget.onSend('Procurar por ideias sobre...');
        }),
        const SizedBox(height: 12),
        _buildEmptyStateItem(context, Icons.add_task, 'Criar uma lista de tarefas', () {
          widget.onSend('Crie uma lista de tarefas');
        }),
      ],
    );
  }

  Widget _buildEmptyStateItem(BuildContext context, IconData icon, String text, VoidCallback onTap) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text, 
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
