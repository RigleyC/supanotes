class SSEChatEvent {
  const SSEChatEvent({
    required this.type,
    this.sessionId = '',
    this.messageId = '',
    this.sequence = 0,
    this.payload = const {},
  });

  final String type;
  final String sessionId;
  final String messageId;
  final int sequence;
  final Map<String, dynamic> payload;

  factory SSEChatEvent.fromJson(Map<String, dynamic> json) {
    final payload = json['payload'];
    if (payload is Map<String, dynamic>) {
      return SSEChatEvent(
        type: json['type'] as String? ?? 'unknown',
        sessionId: json['session_id'] as String? ?? '',
        messageId: json['message_id'] as String? ?? '',
        sequence: json['sequence'] as int? ?? 0,
        payload: payload,
      );
    }

    if (json.containsKey('delta')) {
      return SSEChatEvent(
        type: 'content_delta',
        payload: {'delta': json['delta']},
      );
    }
    if (json['done'] == true) {
      return const SSEChatEvent(type: 'message_finished');
    }
    if (json.containsKey('type')) {
      return SSEChatEvent(
        type: json['type'] as String? ?? 'unknown',
        payload: {'data': json['data']},
      );
    }
    return const SSEChatEvent(type: 'unknown');
  }

  String? get delta => payload['delta'] as String?;
  String? get data => payload['data'] as String?;
  String? get toolName => payload['name'] as String?;
  String? get toolLabel => payload['label'] as String?;
  String? get confirmationToolName => payload['tool_name'] as String?;
  String? get confirmationLabel => payload['label'] as String?;
  String? get errorMessage => payload['message'] as String?;
  String? get finalContent => payload['content'] as String?;

  bool get isContentDelta => type == 'content_delta';
  bool get isToolUse => type == 'tool_use' || type == 'tool_started';
  bool get isToolResult => type == 'tool_result' || type == 'tool_finished';
  bool get isToolStarted => type == 'tool_started';
  bool get isToolFinished => type == 'tool_finished';
  bool get isToolFailed => type == 'tool_failed';
  bool get isConfirmationRequired => type == 'confirmation_required';
  bool get isDone => type == 'done' || type == 'message_finished';
  bool get isError => type == 'error';
}
