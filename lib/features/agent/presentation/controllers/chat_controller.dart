import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/core/api/api_exceptions.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/features/agent/data/chat_repository.dart';
import 'package:supanotes/features/agent/data/chat_sse.dart';
import 'package:supanotes/features/agent/domain/message_model.dart';
import 'package:supanotes/features/agent/domain/session_manager.dart';

typedef ChatState = ({
  List<MessageModel> messages,
  bool isStreaming,
});

final chatControllerProvider = NotifierProvider<ChatController, AsyncValue<ChatState>>(
  ChatController.new,
);

class ChatController extends Notifier<AsyncValue<ChatState>> {
  StreamSubscription<String>? _sseSub;

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
      state = AsyncValue.data((messages: messages, isStreaming: false));
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

    state = AsyncValue.data((
      messages: [...currentMessages, pending, initialAssistant],
      isStreaming: true,
    ));

    _sseSub?.cancel();
    final sse = ChatSSE(apiClient: ref.read(apiClientProvider));

    final messagesWithoutAssistant = [...currentMessages, pending];
    final buffer = StringBuffer();

    _sseSub = sse.streamChat(
      sessionId: sessionId,
      message: trimmed,
    ).listen(
      (delta) {
        buffer.write(delta);
        final updatedAssistant = initialAssistant.copyWith(
          content: buffer.toString(),
        );
        state = AsyncValue.data((
          messages: [...messagesWithoutAssistant, updatedAssistant],
          isStreaming: true,
        ));
      },
      onError: (Object e, StackTrace st) {
        state = AsyncValue.error(
          e is ApiException ? e.message : e.toString(),
          st,
        );
      },
      onDone: () {
        final current = state.value;
        if (current != null) {
          state = AsyncValue.data((
            messages: current.messages,
            isStreaming: false,
          ));
        }
      },
    );
  }
}
