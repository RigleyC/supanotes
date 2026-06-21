import 'package:flutter_gen_ai_chat_ui/flutter_gen_ai_chat_ui.dart';

import 'package:supanotes/features/agent/domain/message_model.dart';
import 'package:supanotes/features/agent/presentation/controllers/chat_controller.dart';

final ChatUser agentChatCurrentUser = ChatUser(
  id: 'agent-chat-current-user',
  name: 'Você',
  role: 'user',
);

final ChatUser agentChatAssistantUser = ChatUser(
  id: 'agent-chat-assistant',
  name: 'Agente',
  role: 'bot',
);

final ChatUser agentChatSystemUser = ChatUser(
  id: 'agent-chat-system',
  name: 'Sistema',
  role: 'system',
);

List<ChatMessage> toGenAiChatMessages(
  List<MessageModel> messages, {
  List<ChatToolAction> actions = const [],
}) {
  final result = <ChatMessage>[
    for (final message in messages)
      if (message.content.trim().isNotEmpty)
        _toChatMessage(message),
  ];

  if (actions.isNotEmpty) {
    result.add(
      ChatMessage.rich(
        user: agentChatSystemUser,
        resultKind: 'action_timeline',
        data: {
          'actions': actions,
        },
      ),
    );
  }

  return result;
}

ChatMessage _toChatMessage(MessageModel message) {
  return ChatMessage(
    text: message.content,
    user: _userForRole(message.role),
    createdAt: message.createdAt,
    isMarkdown: message.role == MessageRole.assistant,
    customProperties: {'id': message.id},
  );
}

ChatUser _userForRole(MessageRole role) {
  switch (role) {
    case MessageRole.user:
      return agentChatCurrentUser;
    case MessageRole.assistant:
      return agentChatAssistantUser;
    case MessageRole.system:
    case MessageRole.tool:
      return agentChatSystemUser;
  }
}
