import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/core/api/api_exceptions.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/features/agent/data/chat_repository.dart';
import 'package:supanotes/features/agent/data/chat_sse.dart';
import 'package:supanotes/features/agent/domain/message_model.dart';
import 'package:supanotes/features/agent/domain/session_manager.dart';
import 'package:supanotes/features/agent/domain/sse_chat_event.dart';
import 'package:supanotes/features/agent/domain/tool_confirmation.dart';

enum ChatToolActionStatus {
  running,
  completed,
  failed,
  confirmationRequired,
  confirmed,
  cancelled,
}

typedef ChatToolAction = ({
  String id,
  String name,
  String label,
  ChatToolActionStatus status,
  String? message,
  String? confirmationId,
});

typedef ChatState = ({
  List<MessageModel> messages,
  List<ChatToolAction> actions,
  bool isStreaming,
  String? loadingLabel,
});

ChatState chatState({
  List<MessageModel> messages = const [],
  List<ChatToolAction> actions = const [],
  bool isStreaming = false,
  String? loadingLabel,
}) {
  return (
    messages: messages,
    actions: actions,
    isStreaming: isStreaming,
    loadingLabel: loadingLabel,
  );
}

// NOT autoDispose: the SSE stream must stay alive across widget
// unmount/remount to avoid killing in-flight tool confirmations.
final chatControllerProvider =
    AsyncNotifierProvider<ChatController, ChatState>(ChatController.new);

class ChatController extends AsyncNotifier<ChatState> {
  StreamSubscription<SSEChatEvent>? _sseSub;

  @override
  Future<ChatState> build() async {
    ref.watch(sessionResetProvider);
    final sessionId = ref.watch(sessionManagerProvider);
    ref.onDispose(() => _sseSub?.cancel());

    try {
      final messages = await ref
          .read(chatRepositoryProvider)
          .getHistory(sessionId);
      return chatState(messages: messages);
    } on ApiException catch (e, _) {
      throw e.message;
    } catch (e, _) {
      rethrow;
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

    state = AsyncValue.data(
      chatState(
        messages: [...currentMessages, pending, initialAssistant],
        actions: const [],
        isStreaming: true,
        loadingLabel: 'Pensando...',
      ),
    );

    final sse = ref.read(chatSSEProvider);
    if (_sseSub != null) {
      sse.cancel();
      _sseSub?.cancel();
    }

    final messagesWithoutAssistant = [...currentMessages, pending];
    final buffer = StringBuffer();

    void progress({
      List<ChatToolAction>? actions,
      String? content,
      bool? isStreaming,
      String? loadingLabel,
    }) {
      final current = state.value;
      state = AsyncValue.data(
        chatState(
          messages: [
            ...messagesWithoutAssistant,
            initialAssistant.copyWith(
              content: content ?? buffer.toString(),
            ),
          ],
          actions: actions ?? current?.actions ?? const [],
          isStreaming: isStreaming ?? true,
          loadingLabel: loadingLabel ?? current?.loadingLabel,
        ),
      );
    }

    _sseSub = sse
        .streamChat(sessionId: sessionId, message: trimmed)
        .listen(
          (event) {
            if (event.type == 'message_started') {
              final label = event.payload['label'] as String?;
              if (label != null && label.isNotEmpty) {
                progress(loadingLabel: label);
              }
            } else if (event.isContentDelta && event.delta != null) {
              buffer.write(event.delta);
              progress();
            } else if (event.isToolStarted) {
              final currentActions = state.value?.actions ?? const [];
              progress(
                actions: _upsertAction(
                  currentActions,
                  (
                    id: _actionIdFor(event),
                    name: event.toolName ?? 'tool',
                    label: event.toolLabel ?? 'Executando ação',
                    status: ChatToolActionStatus.running,
                    message: null,
                    confirmationId: null,
                  ),
                ),
              );
            } else if (event.isToolFinished) {
              final currentActions = state.value?.actions ?? const [];
              progress(
                actions: _upsertAction(
                  currentActions,
                  (
                    id: _actionIdFor(event),
                    name: event.toolName ?? 'tool',
                    label: event.toolLabel ?? 'Executando ação',
                    status: ChatToolActionStatus.completed,
                    message: null,
                    confirmationId: null,
                  ),
                ),
              );
            } else if (event.isToolFailed || event.isToolResult) {
              final currentActions = state.value?.actions ?? const [];
              progress(
                actions: _upsertAction(
                  currentActions,
                  (
                    id: _actionIdFor(event),
                    name: event.toolName ?? 'tool',
                    label: event.toolLabel ?? 'Executando ação',
                    status: ChatToolActionStatus.failed,
                    message: event.errorMessage ?? event.data,
                    confirmationId: null,
                  ),
                ),
              );
            } else if (event.isConfirmationRequired) {
              final currentActions = state.value?.actions ?? const [];
              progress(
                actions: _upsertAction(
                  currentActions,
                  (
                    id: _actionIdFor(event),
                    name: event.confirmationToolName ??
                        event.toolName ??
                        'tool',
                    label: event.confirmationLabel ??
                        event.toolLabel ??
                        'Executando ação',
                    status: ChatToolActionStatus.confirmationRequired,
                    message: null,
                    confirmationId: event.confirmationId,
                  ),
                ),
              );
            } else if (event.isDone) {
              final content = event.finalContent ?? buffer.toString();
              progress(content: content, isStreaming: false);
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
              progress(isStreaming: false);
            }
          },
        );
  }

  Future<void> resolveToolConfirmation(
    String confirmationId, {
    required bool approved,
  }) async {
    final current = state.value;
    if (current == null) return;

    try {
      final result = await ref.read(chatRepositoryProvider).resolveToolConfirmation(
            confirmationId: confirmationId,
            approved: approved,
          );
      final nextStatus = result.status == ConfirmationStatus.approved
          ? ChatToolActionStatus.confirmed
          : ChatToolActionStatus.cancelled;
      final nextActions = [
        for (final action in current.actions)
          if (action.confirmationId == confirmationId)
            (
              id: action.id,
              name: action.name,
              label: action.label,
              status: nextStatus,
              message: result.message,
              confirmationId: action.confirmationId,
            )
          else
            action,
      ];
      final nextMessages = result.message.trim().isEmpty
          ? current.messages
          : [
              ...current.messages,
              MessageModel(
                id: 'tool-confirmation-${DateTime.now().microsecondsSinceEpoch}',
                sessionId: ref.read(sessionManagerProvider),
                role: MessageRole.tool,
                content: result.message,
                createdAt: DateTime.now(),
              ),
            ];
      state = AsyncValue.data(chatState(
        messages: nextMessages,
        actions: nextActions,
        isStreaming: current.isStreaming,
      ));
    } on ApiException catch (e, st) {
      // ignore: invalid_use_of_internal_member
      state = AsyncValue<ChatState>.error(e.message, st).copyWithPrevious(state);
    }
  }

  List<ChatToolAction> _upsertAction(
    List<ChatToolAction> actions,
    ChatToolAction next,
  ) {
    final index = actions.indexWhere((action) => action.id == next.id);
    if (index == -1) return [...actions, next];
    return [
      ...actions.take(index),
      next,
      ...actions.skip(index + 1),
    ];
  }

  String _actionIdFor(SSEChatEvent event) {
    return event.confirmationId ??
        event.toolName ??
        event.confirmationToolName ??
        'tool-${event.sequence}';
  }

  void _setRecoverableError(String message, String retryMessage) {
    final current = state.value;
    if (current == null) {
      state = AsyncValue<ChatState>.error(message, StackTrace.current);
      return;
    }
    final nonStreamingState = AsyncValue.data(
      chatState(
        messages: current.messages,
        actions: current.actions,
        isStreaming: false,
      ),
    );
    // ignore: invalid_use_of_internal_member
    state = AsyncValue<ChatState>.error(message, StackTrace.current).copyWithPrevious(nonStreamingState);
  }

  Future<void> retryLastMessage() async {
    final messages = state.value?.messages;
    if (messages == null || messages.isEmpty) return;
    
    MessageModel? lastUserMsg;
    for (int i = messages.length - 1; i >= 0; i--) {
      if (messages[i].role == MessageRole.user) {
        lastUserMsg = messages[i];
        break;
      }
    }
    
    if (lastUserMsg == null || lastUserMsg.content.trim().isEmpty) return;
    await sendMessage(lastUserMsg.content);
  }

  Future<void> cancelStreaming() async {
    ref.read(chatSSEProvider).cancel();
    await _sseSub?.cancel();
    _sseSub = null;
    final current = state.value;
    if (current == null) return;
    state = AsyncValue.data(
      chatState(
        messages: current.messages,
        actions: current.actions,
        isStreaming: false,
      ),
    );
  }
}
