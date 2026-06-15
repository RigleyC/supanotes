class SSEChatEvent {
  final String type;
  final String? delta;
  final String? data;
  final bool? done;

  SSEChatEvent({
    required this.type,
    this.delta,
    this.data,
    this.done,
  });

  factory SSEChatEvent.fromJson(Map<String, dynamic> json) {
    if (json.containsKey('delta')) {
      return SSEChatEvent(
        type: 'content_delta',
        delta: json['delta'] as String?,
      );
    } else if (json['done'] == true) {
      return SSEChatEvent(
        type: 'done',
        done: true,
      );
    } else if (json.containsKey('type')) {
      return SSEChatEvent(
        type: json['type'] as String? ?? 'unknown',
        data: json['data'] as String?,
      );
    }
    return SSEChatEvent(type: 'unknown');
  }

  bool get isContentDelta => type == 'content_delta';
  bool get isToolUse => type == 'tool_use';
  bool get isToolResult => type == 'tool_result';
  bool get isDone => type == 'done';
  bool get isError => type == 'error';
}
