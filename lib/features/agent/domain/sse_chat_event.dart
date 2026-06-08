class SSEChatEvent {
  final String type;
  final String data;
  final Map<String, dynamic>? raw;

  SSEChatEvent({required this.type, required this.data, this.raw});

  factory SSEChatEvent.fromJson(Map<String, dynamic> json) {
    return SSEChatEvent(
      type: json['type'] as String? ?? '',
      data: json['data'] as String? ?? '',
      raw: json,
    );
  }

  bool get isContentDelta => type == 'content_delta';
  bool get isToolUse => type == 'tool_use';
  bool get isToolResult => type == 'tool_result';
  bool get isDone => type == 'done';
  bool get isError => type == 'error';
}
