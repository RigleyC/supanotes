import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/agent/domain/message_model.dart';
import 'package:supanotes/features/agent/presentation/chat_message_adapter.dart';
import 'package:supanotes/features/agent/presentation/controllers/chat_controller.dart';

void main() {
  MessageModel message({
    required String id,
    required MessageRole role,
    required String content,
  }) {
    return MessageModel(
      id: id,
      sessionId: 'session-1',
      role: role,
      content: content,
      createdAt: DateTime.utc(2026, 6, 12, 14, 30),
    );
  }

  test('maps user and assistant messages to gen ai chat users', () {
    final messages = toGenAiChatMessages(
      [
        message(id: 'user-1', role: MessageRole.user, content: 'Oi'),
        message(id: 'assistant-1', role: MessageRole.assistant, content: 'Olá'),
      ],
    );

    expect(messages, hasLength(2));
    expect(messages[0].text, 'Oi');
    expect(messages[0].user.id, agentChatCurrentUser.id);
    expect(messages[0].customProperties?['id'], 'user-1');
    expect(messages[1].user.id, agentChatAssistantUser.id);
  });

  test('maps tool actions to single action_timeline message', () {
    final messages = toGenAiChatMessages(
      const [],
      actions: [
        (
          id: 'action-1',
          name: 'update_note',
          label: 'Atualizando notas',
          status: ChatToolActionStatus.confirmationRequired,
          message: null,
          confirmationId: 'confirmation-1',
        ),
      ],
    );

    expect(messages, hasLength(1));
    final data = messages.single.customProperties!;
    expect(data['resultKind'], 'action_timeline');
    
    final actionsList = (data['resultData'] as Map)['actions'] as List<ChatToolAction>;
    expect(actionsList, hasLength(1));
    expect(actionsList[0].id, 'action-1');
    expect(actionsList[0].confirmationId, 'confirmation-1');
    expect(actionsList[0].label, 'Atualizando notas');
  });

  test('maps multiple running and completed actions to single action_timeline message', () {
    final messages = toGenAiChatMessages(
      const [],
      actions: [
        (
          id: 'action-1',
          name: 'search_notes',
          label: 'Buscando notas',
          status: ChatToolActionStatus.running,
          message: null,
          confirmationId: null,
        ),
        (
          id: 'action-2',
          name: 'search_notes',
          label: 'Buscando notas',
          status: ChatToolActionStatus.completed,
          message: null,
          confirmationId: null,
        ),
      ],
    );

    expect(messages, hasLength(1));
    final data = messages.single.customProperties!;
    expect(data['resultKind'], 'action_timeline');
    
    final actionsList = (data['resultData'] as Map)['actions'] as List<ChatToolAction>;
    expect(actionsList, hasLength(2));
    expect(actionsList[0].status, ChatToolActionStatus.running);
    expect(actionsList[1].status, ChatToolActionStatus.completed);
  });

  test('resolves known chat users', () {
    expect(agentChatCurrentUser.id, 'agent-chat-current-user');
    expect(agentChatCurrentUser.name, 'Você');
    expect(agentChatAssistantUser.id, 'agent-chat-assistant');
    expect(agentChatAssistantUser.name, 'Agente');
  });
}
