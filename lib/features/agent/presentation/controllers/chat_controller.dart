// ignore_for_file: invalid_use_of_internal_member
import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/core/api/api_exceptions.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/features/agent/data/chat_repository.dart';
import 'package:supanotes/features/agent/data/chat_sse.dart';
import 'package:supanotes/features/agent/domain/message_model.dart';
import 'package:supanotes/features/agent/domain/session_manager.dart';
import 'package:supanotes/features/agent/domain/sse_chat_event.dart';

typedef ChatState = ({
  List<MessageModel> messages,
  bool isStreaming,
});

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
    String currentToolStatus = '';

    _sseSub = sse.streamChat(
      sessionId: sessionId,
      message: trimmed,
    ).listen(
      (event) {
        if (event.type == 'content_delta' && event.delta != null) {
          buffer.write(event.delta);
          currentToolStatus = ''; // Clear tool status when text response starts
          final updatedAssistant = initialAssistant.copyWith(
            content: buffer.toString(),
          );
          state = AsyncValue.data((
            messages: [...messagesWithoutAssistant, updatedAssistant],
            isStreaming: true,
          ));
        } else if (event.type == 'tool_use' && event.data != null) {
          try {
            final toolCall = jsonDecode(event.data!) as Map<String, dynamic>;
            final toolName = toolCall['name'] as String? ?? 'processamento';
            
            currentToolStatus = '\n\n*(Pensando... executando ação: $toolName)*';
            final updatedAssistant = initialAssistant.copyWith(
              content: buffer.toString() + currentToolStatus,
            );
            state = AsyncValue.data((
              messages: [...messagesWithoutAssistant, updatedAssistant],
              isStreaming: true,
            ));
          } catch (_) {}
        } else if (event.type == 'tool_result') {
          currentToolStatus = '\n\n*(Pensando... processando resultado)*';
          final updatedAssistant = initialAssistant.copyWith(
            content: buffer.toString() + currentToolStatus,
          );
          state = AsyncValue.data((
            messages: [...messagesWithoutAssistant, updatedAssistant],
            isStreaming: true,
          ));
        } else if (event.type == 'done') {
          final current = state.value;
          if (current != null) {
            final finalAssistant = initialAssistant.copyWith(
              content: buffer.toString(),
            );
            state = AsyncValue.data((
              messages: [...messagesWithoutAssistant, finalAssistant],
              isStreaming: false,
            ));
          }
        }
      },
      onError: (Object e, StackTrace st) {
        final messages = state.value?.messages ?? currentMessages;
        final errorState = AsyncValue<ChatState>.data((
          messages: messages,
          isStreaming: false,
        ));
        state = AsyncError<ChatState>(
          e is ApiException ? e.message : e.toString(),
          st,
        ).copyWithPrevious(errorState);
      },
      onDone: () {
        final current = state.value;
        if (current != null) {
          final finalAssistant = initialAssistant.copyWith(
            content: buffer.toString(),
          );
          state = AsyncValue.data((
            messages: [...messagesWithoutAssistant, finalAssistant],
            isStreaming: false,
          ));
        }
      },
    );
  }
}
