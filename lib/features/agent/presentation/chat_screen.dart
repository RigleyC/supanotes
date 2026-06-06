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

import 'package:supanotes/core/api/api_exceptions.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/widgets/empty_state.dart';
import 'package:supanotes/shared/widgets/error_snackbar.dart';

import '../data/chat_repository.dart';
import '../domain/message_model.dart';
import '../domain/session_manager.dart';
import 'widgets/chat_input.dart';
import 'widgets/message_bubble.dart';
import 'widgets/new_session_button.dart';
import 'widgets/typing_indicator.dart';

// ---------------------------------------------------------------------------
// Controller
// ---------------------------------------------------------------------------

/// Owns the chat list + loading/error state.
///
/// Watches [sessionManagerProvider] so that rotating the session id
/// (via the "Nova conversa" button) triggers a fresh history load and
/// a clean state. All public methods are safe to call from the UI; they
/// mutate [state] in place and the screen reacts via [ref.watch] and
/// [ref.listen].
class ChatController extends Notifier<ChatListState> {
  @override
  ChatListState build() {
    final sessionId = ref.watch(sessionManagerProvider);
    Future.microtask(() => _loadHistory(sessionId));
    return const ChatListState(messages: <MessageModel>[], isLoading: true);
  }

  Future<void> _loadHistory(String sessionId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final messages =
          await ref.read(chatRepositoryProvider).getHistory(sessionId);
      if (ref.read(sessionManagerProvider) != sessionId) return;
      state = state.copyWith(messages: messages, isLoading: false);
    } on ApiException catch (e) {
      if (ref.read(sessionManagerProvider) != sessionId) return;
      state = state.copyWith(isLoading: false, error: e.message);
    }
  }

  /// Optimistically appends the user message, calls
  /// `POST /api/v1/agent/chat`, then appends the assistant reply. On
  /// failure the optimistic message is rolled back and [state.error] is
  /// set so the screen can surface it as a snackbar.
  Future<void> sendMessage(String content) async {
    final sessionId = ref.read(sessionManagerProvider);
    final pending = MessageModel(
      id: 'pending-${DateTime.now().microsecondsSinceEpoch}',
      sessionId: sessionId,
      role: MessageRole.user,
      content: content,
      createdAt: DateTime.now(),
    );
    state = state.copyWith(
      messages: <MessageModel>[...state.messages, pending],
      isLoading: true,
      clearError: true,
    );
    try {
      final response = await ref.read(chatRepositoryProvider).sendMessage(
            sessionId: sessionId,
            message: content,
          );
      if (ref.read(sessionManagerProvider) != sessionId) return;
      final assistant = MessageModel(
        id: 'response-${DateTime.now().microsecondsSinceEpoch}',
        sessionId: sessionId,
        role: MessageRole.assistant,
        content: response,
        createdAt: DateTime.now(),
      );
      state = state.copyWith(
        messages: <MessageModel>[...state.messages, assistant],
        isLoading: false,
      );
    } on ApiException catch (e) {
      if (ref.read(sessionManagerProvider) != sessionId) return;
      state = state.copyWith(
        messages:
            state.messages.where((m) => m.id != pending.id).toList(growable: false),
        isLoading: false,
        error: e.message,
      );
    }
  }
}

final chatControllerProvider =
    NotifierProvider<ChatController, ChatListState>(ChatController.new);

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

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
    ref.listen<ChatListState>(chatControllerProvider, (prev, next) {
      final messageCountChanged = prev?.messages.length != next.messages.length;
      final loadingChanged = prev?.isLoading != next.isLoading;
      if (messageCountChanged || loadingChanged) {
        _scrollToBottom();
      }
      if (next.error != null && next.error != prev?.error) {
        showErrorSnackBar(context, message: next.error!);
      }
    });

    final state = ref.watch(chatControllerProvider);
    final isLoading = state.isLoading;

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
              child: _buildBody(state, isLoading),
            ),
            ChatInput(
              enabled: !isLoading,
              onSend: (text) =>
                  ref.read(chatControllerProvider.notifier).sendMessage(text),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ChatListState state, bool isLoading) {
    if (state.messages.isEmpty && !isLoading) {
      return const EmptyState(
        icon: Icons.chat_bubble_outline,
        title: 'Comece uma conversa',
        subtitle: 'Pergunte algo ao agent e a resposta aparecerá aqui.',
      );
    }
    if (state.messages.isEmpty && isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      itemCount: state.messages.length + (isLoading ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == state.messages.length) {
          return const TypingIndicator();
        }
        return MessageBubble(message: state.messages[index]);
      },
    );
  }
}
