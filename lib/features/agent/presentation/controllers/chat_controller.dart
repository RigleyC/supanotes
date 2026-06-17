import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/core/api/api_exceptions.dart';
import 'package:supanotes/features/agent/data/chat_repository.dart';
import 'package:supanotes/features/agent/data/chat_sse.dart';
import 'package:supanotes/features/agent/domain/message_model.dart';
import 'package:supanotes/features/agent/domain/session_manager.dart';
import 'package:supanotes/features/agent/domain/sse_chat_event.dart';

typedef ChatState = ({
  List<MessageModel> messages,
  bool isStreaming,
  String? activeToolLabel,
  String? errorMessage,
  String? retryMessage,
});

ChatState chatState({
  List<MessageModel> messages = const [],
  bool isStreaming = false,
  String? activeToolLabel,
  String? errorMessage,
  String? retryMessage,
}) {
  return (
    messages: messages,
    isStreaming: isStreaming,
    activeToolLabel: activeToolLabel,
    errorMessage: errorMessage,
    retryMessage: retryMessage,
  );
}

final chatControllerProvider = NotifierProvider<ChatController, AsyncValue<ChatState>>(
  ChatController.new,
);

class ChatController extends Notifier<AsyncValue<ChatState>> {
  StreamSubscription<SSEChatEvent>? _sseSub;

  @override
  AsyncValue<ChatState> build() {
    final sessionId = ref.watch(sessionManagerProvider);
    ref.onDispose(() => _sseSub?.cancel());
    
    Future.microtask(() => _loadHistory(sessionId));
    return const AsyncValue.loading();
  }

  Future<void> _loadHistory(String sessionId) async {
    state = const AsyncValue.loading();
    try {
      final messages = await ref.read(chatRepositoryProvider).getHistory(sessionId);
      state = AsyncValue.data(chatState(messages: messages));
    } on ApiException catch (e, st) {
      state = AsyncValue.error(e.message, st);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> sendMessage(String content) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return;

    final sessionId = ref.read(sessionManagerProvider);
    final currentMessages = state.value?.messages ?? [];

    final pending = MessageModel(
      id: 'pending-${DateTime.now().microsecondsSinceEpoch}',
      sessionId: sessionId,
      role: MessageRole.user,
      content: trimmed,
      createdAt: DateTime.now(),
    );

    final assistantId = 'assistant-${DateTime.now().microsecondsSinceEpoch}';
    final initialAssistant = MessageModel(
      id: assistantId,
      sessionId: sessionId,
      role: MessageRole.assistant,
      content: '',
      createdAt: DateTime.now(),
    );

    state = AsyncValue.data(chatState(
      messages: [...currentMessages, pending, initialAssistant],
      isStreaming: true,
      retryMessage: trimmed,
    ));

    _sseSub?.cancel();
    final sse = ref.read(chatSSEProvider);

    final messagesWithoutAssistant = [...currentMessages, pending];
    final buffer = StringBuffer();

    _sseSub = sse.streamChat(
      sessionId: sessionId,
      message: trimmed,
    ).listen(
      (event) {
        if (event.isContentDelta && event.delta != null) {
          buffer.write(event.delta);
          state = AsyncValue.data(chatState(
            messages: [...messagesWithoutAssistant, initialAssistant.copyWith(content: buffer.toString())],
            isStreaming: true,
            retryMessage: trimmed,
          ));
        } else if (event.isToolStarted) {
          state = AsyncValue.data(chatState(
            messages: [...messagesWithoutAssistant, initialAssistant.copyWith(content: buffer.toString())],
            isStreaming: true,
            activeToolLabel: event.toolLabel ?? 'Executando acao',
            retryMessage: trimmed,
          ));
        } else if (event.isToolFinished || event.isToolFailed || event.isToolResult) {
          state = AsyncValue.data(chatState(
            messages: [...messagesWithoutAssistant, initialAssistant.copyWith(content: buffer.toString())],
            isStreaming: true,
            retryMessage: trimmed,
          ));
        } else if (event.isDone) {
          final content = event.finalContent ?? buffer.toString();
          state = AsyncValue.data(chatState(
            messages: [...messagesWithoutAssistant, initialAssistant.copyWith(content: content)],
            isStreaming: false,
            retryMessage: trimmed,
          ));
        }
      },
      onError: (Object e, StackTrace st) {
        _setRecoverableError(
          e is ApiException ? e.message : e.toString(),
          trimmed,
        );
      },
      onDone: () {
        final current = state.value;
        if (current != null && current.isStreaming) {
          state = AsyncValue.data(chatState(
            messages: [...messagesWithoutAssistant, initialAssistant.copyWith(content: buffer.toString())],
            isStreaming: false,
            retryMessage: trimmed,
          ));
        }
      },
    );
  }

  void _setRecoverableError(String message, String retryMessage) {
    final current = state.value;
    if (current == null) {
      state = AsyncValue.error(message, StackTrace.current);
      return;
    }
    state = AsyncValue.data(chatState(
      messages: current.messages,
      isStreaming: false,
      errorMessage: message,
      retryMessage: retryMessage,
    ));
  }

  Future<void> retryLastMessage() async {
    final retry = state.value?.retryMessage;
    if (retry == null || retry.trim().isEmpty) return;
    await sendMessage(retry);
  }

  Future<void> cancelStreaming() async {
    await _sseSub?.cancel();
    _sseSub = null;
    final current = state.value;
    if (current == null) return;
    state = AsyncValue.data(chatState(
      messages: current.messages,
      isStreaming: false,
      retryMessage: current.retryMessage,
    ));
  }
}
