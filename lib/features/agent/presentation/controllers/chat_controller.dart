import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/core/api/api_exceptions.dart';
import 'package:supanotes/features/agent/data/chat_repository.dart';
import 'package:supanotes/features/agent/domain/message_model.dart';
import 'package:supanotes/features/agent/domain/session_manager.dart';

typedef ChatState = ({
  List<MessageModel> messages,
  bool isLoading,
  String? error,
});

final chatControllerProvider =
    NotifierProvider<ChatController, ChatState>(ChatController.new);

class ChatController extends Notifier<ChatState> {
  @override
  ChatState build() {
    final sessionId = ref.watch(sessionManagerProvider);
    Future.microtask(() => _loadHistory(sessionId));
    return (messages: [], isLoading: true, error: null);
  }

  Future<void> _loadHistory(String sessionId) async {
    state = (messages: state.messages, isLoading: true, error: null);
    try {
      final messages =
          await ref.read(chatRepositoryProvider).getHistory(sessionId);
      if (ref.read(sessionManagerProvider) != sessionId) return;
      state = (messages: messages, isLoading: false, error: null);
    } on ApiException catch (e) {
      if (ref.read(sessionManagerProvider) != sessionId) return;
      state = (messages: state.messages, isLoading: false, error: e.message);
    }
  }

  Future<void> loadHistory() async {
    final sessionId = ref.read(sessionManagerProvider);
    await _loadHistory(sessionId);
  }

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

    state = (
      messages: [...state.messages, pending],
      isLoading: true,
      error: null,
    );

    try {
      final response = await ref.read(chatRepositoryProvider).sendMessage(
            sessionId: sessionId,
            message: trimmed,
          );
      if (ref.read(sessionManagerProvider) != sessionId) return;
      final assistant = MessageModel(
        id: 'response-${DateTime.now().microsecondsSinceEpoch}',
        sessionId: sessionId,
        role: MessageRole.assistant,
        content: response,
        createdAt: DateTime.now(),
      );
      state = (
        messages: [...state.messages, assistant],
        isLoading: false,
        error: null,
      );
    } on ApiException catch (e) {
      if (ref.read(sessionManagerProvider) != sessionId) return;
      state = (
        messages:
            state.messages.where((m) => m.id != pending.id).toList(growable: false),
        isLoading: false,
        error: e.message,
      );
    }
  }
}
