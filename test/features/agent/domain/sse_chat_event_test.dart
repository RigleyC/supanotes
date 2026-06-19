import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/agent/domain/sse_chat_event.dart';

void main() {
  test('parses normalized content delta event', () {
    final event = SSEChatEvent.fromJson(const {
      'session_id': 'session-1',
      'message_id': 'message-1',
      'sequence': 2,
      'type': 'content_delta',
      'payload': {'delta': 'Oi'},
    });

    expect(event.type, 'content_delta');
    expect(event.sessionId, 'session-1');
    expect(event.messageId, 'message-1');
    expect(event.sequence, 2);
    expect(event.delta, 'Oi');
    expect(event.isContentDelta, isTrue);
  });

  test('parses normalized tool started event', () {
    final event = SSEChatEvent.fromJson(const {
      'session_id': 'session-1',
      'message_id': 'message-1',
      'sequence': 3,
      'type': 'tool_started',
      'payload': {'name': 'search_notes', 'label': 'Buscando notas'},
    });

    expect(event.type, 'tool_started');
    expect(event.toolName, 'search_notes');
    expect(event.toolLabel, 'Buscando notas');
    expect(event.isToolStarted, isTrue);
  });

  test('parses confirmation_required with confirmation_id', () {
  final event = SSEChatEvent.fromJson({
    'type': 'confirmation_required',
    'payload': {
      'confirmation_id': 'confirmation-1',
      'tool_name': 'update_note',
      'label': 'Atualizando notas',
    },
  });

  expect(event.isConfirmationRequired, isTrue);
  expect(event.confirmationId, 'confirmation-1');
  expect(event.confirmationToolName, 'update_note');
  expect(event.confirmationLabel, 'Atualizando notas');
});

test('parses normalized message finished event', () {
    final event = SSEChatEvent.fromJson(const {
      'session_id': 'session-1',
      'message_id': 'message-1',
      'sequence': 4,
      'type': 'message_finished',
      'payload': {'content': 'Pronto'},
    });

    expect(event.finalContent, 'Pronto');
    expect(event.isDone, isTrue);
  });
}
