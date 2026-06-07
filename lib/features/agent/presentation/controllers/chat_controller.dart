import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/features/agent/data/chat_repository.dart';
import 'package:supanotes/features/agent/domain/message_model.dart';

class ChatState {
  final List<MessageModel> messages;
  final bool isLoading;
  final String? error;

  const ChatState({
    this.messages = const [],
    this.isLoading = false,
    this.error,
  });

  ChatState copyWith({
    List<MessageModel>? messages,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) =>
      ChatState(
        messages: messages ?? this.messages,
        isLoading: isLoading ?? this.isLoading,
        error: clearError ? null : (error ?? this.error),
      );
}

final chatControllerProvider =
    AsyncNotifierProvider<ChatController, ChatState>(
  ChatController.new,
);

class ChatController extends AsyncNotifier<ChatState> {
  @override
  Future<ChatState> build() async {
    return const ChatState();
  }

  Future<void> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final chatRepo = ref.read(chatRepositoryProvider);
    final userMessage = MessageModel(
      id: '',
      sessionId: '',
      role: MessageRole.user,
      content: trimmed,
      createdAt: DateTime.now(),
    );

    state = AsyncValue.data(
      state.value!.copyWith(
        messages: [...state.value!.messages, userMessage],
        isLoading: true,
        clearError: true,
      ),
    );

    try {
      final reply = await chatRepo.sendMessage(
        sessionId: '',
        message: trimmed,
      );
      final assistantMessage = MessageModel(
        id: '',
        sessionId: '',
        role: MessageRole.assistant,
        content: reply,
        createdAt: DateTime.now(),
      );
      state = AsyncValue.data(
        state.value!.copyWith(
          messages: [...state.value!.messages, assistantMessage],
          isLoading: false,
        ),
      );
    } catch (e) {
      state = AsyncValue.data(
        state.value!.copyWith(
          isLoading: false,
          error: e.toString(),
        ),
      );
    }
  }

  Future<void> loadHistory() async {
    state = AsyncValue.data(state.value!.copyWith(isLoading: true));
    try {
      final chatRepo = ref.read(chatRepositoryProvider);
      final messages = await chatRepo.getHistory('');
      state = AsyncValue.data(
        state.value!.copyWith(messages: messages, isLoading: false),
      );
    } catch (e) {
      state = AsyncValue.data(
        state.value!.copyWith(isLoading: false, error: e.toString()),
      );
    }
  }
}
