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
  bool loaded,
  bool streaming,
  String? error,
});

final chatControllerProvider =
    NotifierProvider.autoDispose<ChatController, ChatState>(
  ChatController.new,
);

class ChatController extends Notifier<ChatState> {
  @override
  ChatState build() {
    final sessionId = ref.watch(sessionManagerProvider);
    ref.onDispose(() => _sseSub?.cancel());
    Future.microtask(() => _loadHistory(sessionId));
    return (messages: const [], loaded: false, streaming: false, error: null);
  }

  Future<void> _loadHistory(String sessionId) async {
    try {
      final messages =
          await ref.read(chatRepositoryProvider).getHistory(sessionId);
      if (ref.read(sessionManagerProvider) != sessionId) return;
      state = (messages: messages, loaded: true, streaming: false, error: null);
    } on ApiException catch (e) {
      if (ref.read(sessionManagerProvider) != sessionId) return;
      state = (messages: state.messages, loaded: true, streaming: false, error: e.message);
    }
  }

  Future<void> loadHistory() async {
    final sessionId = ref.read(sessionManagerProvider);
    await _loadHistory(sessionId);
  }

  StreamSubscription<String>? _sseSub;

  Future<void> sendMessage(String content) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return;

    final sessionId = ref.read(sessionManagerProvider);
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

    state = (
      messages: [...state.messages, pending, initialAssistant],
      loaded: true,
      streaming: true,
      error: null,
    );

    _sseSub?.cancel();
    final sse = ChatSSE(apiClient: ref.read(apiClientProvider));
    _sseSub = sse.streamChat(
      sessionId: sessionId,
      message: trimmed,
    ).listen(
      (delta) {
        if (ref.read(sessionManagerProvider) != sessionId) {
          _sseSub?.cancel();
          return;
        }
        final messages = state.messages;
        final idx = messages.indexWhere((m) => m.id == assistantId);
        if (idx == -1) return;
        final updated = messages[idx].copyWith(
          content: messages[idx].content + delta,
        );
        state = (
          messages: [
            ...messages.sublist(0, idx),
            updated,
            ...messages.sublist(idx + 1),
          ],
          loaded: true,
          streaming: true,
          error: null,
        );
      },
      onError: (Object e) {
        if (ref.read(sessionManagerProvider) != sessionId) return;
        state = (
          messages:
              state.messages.where((m) => m.id != assistantId).toList(growable: false),
          loaded: true,
          streaming: false,
          error: e is ApiException ? e.message : e.toString(),
        );
      },
      onDone: () {
        if (ref.read(sessionManagerProvider) != sessionId) return;
        state = (messages: state.messages, loaded: true, streaming: false, error: null);
      },
    );
  }
}
