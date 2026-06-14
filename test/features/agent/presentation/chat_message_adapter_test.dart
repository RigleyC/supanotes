import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/agent/domain/message_model.dart';
import 'package:supanotes/features/agent/presentation/chat_message_adapter.dart';

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

  test('maps user and assistant messages to stable author ids', () {
    final messages = toFlyerMessages(
      [
        message(id: 'user-1', role: MessageRole.user, content: 'Oi'),
        message(
          id: 'assistant-1',
          role: MessageRole.assistant,
          content: 'Como posso ajudar?',
        ),
      ],
      streaming: false,
    );

    expect(messages, hasLength(2));
    expect(messages[0].id, 'user-1');
    expect(messages[0].authorId, agentChatCurrentUserId);
    expect(messages[1].id, 'assistant-1');
    expect(messages[1].authorId, agentChatAssistantUserId);
  });

  test('adds a typing placeholder when assistant is streaming empty content', () {
    final messages = toFlyerMessages(
      [
        message(id: 'user-1', role: MessageRole.user, content: 'Resumo?'),
        message(id: 'assistant-1', role: MessageRole.assistant, content: ''),
      ],
      streaming: true,
    );

    expect(messages, hasLength(2));
    expect(messages.last.id, 'agent-typing-assistant-1');
    expect(messages.last.authorId, agentChatAssistantUserId);
  });

  test('does not add a typing placeholder when assistant already has text', () {
    final messages = toFlyerMessages(
      [
        message(id: 'user-1', role: MessageRole.user, content: 'Resumo?'),
        message(id: 'assistant-1', role: MessageRole.assistant, content: 'Claro'),
      ],
      streaming: true,
    );

    expect(messages, hasLength(2));
    expect(messages.last.id, 'assistant-1');
  });

  test('resolves known chat users', () async {
    final me = await resolveAgentChatUser(agentChatCurrentUserId);
    final assistant = await resolveAgentChatUser(agentChatAssistantUserId);
    final unknown = await resolveAgentChatUser('missing');

    expect(me?.name, 'Voc\u00ea');
    expect(assistant?.name, 'Agent');
    expect(unknown, isNull);
  });
}
