import 'package:flutter_chat_core/flutter_chat_core.dart' as flyer;

import 'package:supanotes/features/agent/domain/message_model.dart';

const String agentChatCurrentUserId = 'agent-chat-current-user';
const String agentChatAssistantUserId = 'agent-chat-assistant';
const String agentChatSystemUserId = 'agent-chat-system';
const String agentChatToolUserId = 'agent-chat-tool';
const String agentChatTypingKind = 'typing';

List<flyer.Message> toFlyerMessages(
  List<MessageModel> messages, {
  required bool streaming,
}) {
  final converted = <flyer.Message>[];
  for (final message in messages) {
    final flyerMessage = _toFlyerMessage(message);
    if (flyerMessage != null) {
      converted.add(flyerMessage);
    }
  }

  if (streaming && messages.isNotEmpty) {
    final last = messages.last;
    if (last.role == MessageRole.assistant && last.content.trim().isEmpty) {
      converted.removeWhere((message) => message.id == last.id);
      converted.add(
        flyer.Message.custom(
          id: 'agent-typing-${last.id}',
          authorId: agentChatAssistantUserId,
          createdAt: last.createdAt,
          metadata: const {'kind': agentChatTypingKind},
        ),
      );
    }
  }

  return converted;
}

flyer.Message? _toFlyerMessage(MessageModel message) {
  final content = message.content.trimRight();
  if (content.isEmpty) {
    return null;
  }

  if (message.role == MessageRole.system) {
    return flyer.Message.system(
      id: message.id,
      authorId: agentChatSystemUserId,
      createdAt: message.createdAt,
      text: content,
    );
  }

  return flyer.Message.text(
    id: message.id,
    authorId: _authorIdForRole(message.role),
    createdAt: message.createdAt,
    text: content,
  );
}

String _authorIdForRole(MessageRole role) {
  switch (role) {
    case MessageRole.user:
      return agentChatCurrentUserId;
    case MessageRole.assistant:
      return agentChatAssistantUserId;
    case MessageRole.system:
      return agentChatSystemUserId;
    case MessageRole.tool:
      return agentChatToolUserId;
  }
}

Future<flyer.User?> resolveAgentChatUser(String id) async {
  switch (id) {
    case agentChatCurrentUserId:
      return const flyer.User(id: agentChatCurrentUserId, name: 'Voc\u00ea');
    case agentChatAssistantUserId:
      return const flyer.User(id: agentChatAssistantUserId, name: 'Agent');
    case agentChatSystemUserId:
      return const flyer.User(id: agentChatSystemUserId, name: 'Sistema');
    case agentChatToolUserId:
      return const flyer.User(id: agentChatToolUserId, name: 'Tool');
    default:
      return null;
  }
}
