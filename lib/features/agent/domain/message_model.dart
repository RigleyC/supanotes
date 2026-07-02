/// Domain model for a single chat message exchanged with the agent.
///
/// Wire shape (from `backend/internal/db/sqlcgen/models.go::Message` and
/// the JSON returned by `GET /api/v1/agent/messages`):
///
/// ```json
/// {
///   "id": "uuid",
///   "user_id": "uuid",
///   "session_id": "uuid",
///   "role": "user" | "assistant" | "system" | "tool",
///   "content": "string",
///   "tool_calls": null | "...",
///   "tool_call_id": null | "uuid",
///   "created_at": "2025-01-01T00:00:00Z"
/// }
/// ```
library;

enum MessageRole { user, assistant, system, tool }

MessageRole messageRoleFromString(String value) {
  switch (value.toLowerCase()) {
    case 'assistant':
      return MessageRole.assistant;
    case 'system':
      return MessageRole.system;
    case 'tool':
      return MessageRole.tool;
    case 'user':
    default:
      return MessageRole.user;
  }
}

class MessageModel {
  const MessageModel({
    required this.id,
    required this.sessionId,
    required this.role,
    required this.content,
    required this.createdAt,
  });

  final String id;
  final String sessionId;
  final MessageRole role;
  final String content;
  final DateTime createdAt;

  MessageModel copyWith({
    String? id,
    String? sessionId,
    MessageRole? role,
    String? content,
    DateTime? createdAt,
  }) {
    return MessageModel(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      role: role ?? this.role,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory MessageModel.fromJson(Map<String, dynamic> json) {
    return MessageModel(
      id: (json['id'] ?? '') as String,
      sessionId: (json['session_id'] ?? '') as String,
      role: messageRoleFromString((json['role'] ?? 'user') as String),
      content: (json['content'] ?? '') as String,
      createdAt:
          DateTime.tryParse((json['created_at'] ?? '') as String) ??
          DateTime.now(),
    );
  }
}
