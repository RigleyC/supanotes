import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/core/api/api_client.dart';
import 'package:supanotes/core/api/auth_interceptor.dart';
import 'package:supanotes/features/agent/data/chat_repository.dart';
import 'package:supanotes/features/agent/data/chat_sse.dart';
import 'package:supanotes/features/agent/domain/message_model.dart';
import 'package:supanotes/features/agent/domain/session_manager.dart';
import 'package:supanotes/features/agent/domain/sse_chat_event.dart';
import 'package:supanotes/features/agent/presentation/controllers/chat_controller.dart';

void main() {
  late StreamController<SSEChatEvent> streamController;
  late _FakeChatSSE fakeSSE;
  late _FakeChatRepository fakeRepo;

  ProviderContainer createContainer({String sessionId = 'session-1'}) {
    streamController = StreamController<SSEChatEvent>.broadcast();
    fakeSSE = _FakeChatSSE(streamController);
    fakeRepo = _FakeChatRepository();

    return ProviderContainer(
      overrides: [
        sessionManagerProvider.overrideWith(
          () => _FakeSessionManager(sessionId),
        ),
        chatRepositoryProvider.overrideWith((ref) => fakeRepo),
        chatSSEProvider.overrideWith((ref) => fakeSSE),
      ],
    );
  }

  tearDown(() {
    streamController.close();
  });

  testWidgets('loadHistory returns chatState with messages', (tester) async {
    final container = createContainer();
    fakeRepo.history = [
      MessageModel(
        id: 'msg-1',
        sessionId: 'session-1',
        role: MessageRole.assistant,
        content: 'Hello',
        createdAt: DateTime.utc(2026, 6, 12),
      ),
    ];

    // trigger lazy provider creation and wait for async build
    await tester.runAsync(() async {
      container.read(chatControllerProvider);
      for (var i = 0; i < 10; i++) {
        await Future(() {});
      }
    });

    final finalState = container.read(chatControllerProvider);
    expect(finalState.isLoading, isFalse);
    expect(finalState.hasError, isFalse);

    final data = finalState.value!;
    expect(data.messages.length, 1);
    expect(data.messages[0].content, 'Hello');
    expect(data.isStreaming, isFalse);
  });

  test('tool_started sets activeToolLabel', () async {
    final container = createContainer();
    final controller = container.read(chatControllerProvider.notifier);

    controller.sendMessage('do something');
    await Future(() {});

    streamController.add(
      SSEChatEvent(
        type: 'tool_started',
        payload: {'name': 'search_notes', 'label': 'Buscando notas'},
      ),
    );

    await Future(() {});

    final state = container.read(chatControllerProvider);
    final data = state.value!;
    expect(data.activeToolLabel, 'Buscando notas');
    expect(data.isStreaming, isTrue);
  });

  test('content_delta updates assistant content without status text', () async {
    final container = createContainer();
    final controller = container.read(chatControllerProvider.notifier);

    controller.sendMessage('write something');
    await Future(() {});

    streamController.add(
      SSEChatEvent(type: 'content_delta', payload: {'delta': 'Here is '}),
    );

    await Future(() {});

    streamController.add(
      SSEChatEvent(type: 'content_delta', payload: {'delta': 'the result'}),
    );

    await Future(() {});

    final state = container.read(chatControllerProvider);
    final data = state.value!;
    expect(data.isStreaming, isTrue);
    expect(data.messages.last.content, 'Here is the result');
    expect(data.messages.last.content.contains('Pensando'), isFalse);
  });

  test('message_finished clears isStreaming', () async {
    final container = createContainer();
    final controller = container.read(chatControllerProvider.notifier);

    controller.sendMessage('finish');
    await Future(() {});

    streamController.add(
      SSEChatEvent(type: 'content_delta', payload: {'delta': 'Final answer'}),
    );

    await Future(() {});

    streamController.add(
      SSEChatEvent(
        type: 'message_finished',
        payload: {'content': 'Final answer'},
      ),
    );

    await Future(() {});

    final state = container.read(chatControllerProvider);
    final data = state.value!;
    expect(data.isStreaming, isFalse);
    expect(data.messages.last.content, 'Final answer');
  });

  test('stream error keeps partial messages and sets errorMessage', () async {
    final container = createContainer();
    final controller = container.read(chatControllerProvider.notifier);

    controller.sendMessage('will error');
    await Future(() {});

    streamController.add(
      SSEChatEvent(type: 'content_delta', payload: {'delta': 'Partial '}),
    );

    await Future(() {});

    streamController.addError('Stream failed');

    await Future(() {});
    await Future(() {});

    final state = container.read(chatControllerProvider);
    final data = state.value;
    expect(data, isNotNull);
    expect(data!.errorMessage, 'Stream failed');
    expect(data.isStreaming, isFalse);
  });

  test('confirmation_required stays visible after message finishes', () async {
    final container = createContainer();
    final controller = container.read(chatControllerProvider.notifier);

    controller.sendMessage('delete a memory');
    await Future(() {});

    streamController.add(
      SSEChatEvent(
        type: 'confirmation_required',
        payload: {
          'tool_name': 'delete_memory',
          'label': 'Apagando memória',
          'args_json': '{"memory_id":"m-1"}',
        },
      ),
    );

    await Future(() {});

    streamController.add(
      SSEChatEvent(
        type: 'message_finished',
        payload: {'content': 'Preciso da sua confirmação antes de aplicar.'},
      ),
    );

    await Future(() {});

    final state = container.read(chatControllerProvider);
    final data = state.value!;
    expect(data.isStreaming, isFalse);
    expect(data.errorMessage, 'Preciso da sua confirmação: Apagando memória');
    expect(data.retryMessage, 'delete a memory');
    expect(
      data.messages.last.content,
      'Preciso da sua confirmação antes de aplicar.',
    );
  });

  test('cancelStreaming clears isStreaming', () async {
    final container = createContainer();
    final controller = container.read(chatControllerProvider.notifier);

    controller.sendMessage('cancel me');
    await Future(() {});
    await Future(() {});

    await controller.cancelStreaming();
    await Future(() {});

    final state = container.read(chatControllerProvider);
    final data = state.value!;
    expect(data.isStreaming, isFalse);
    expect(fakeSSE.cancelCalls, 1);
  });

  test(
    'sendMessage cancels an existing stream before opening another',
    () async {
      final container = createContainer();
      final controller = container.read(chatControllerProvider.notifier);

      controller.sendMessage('first');
      await Future(() {});

      controller.sendMessage('second');
      await Future(() {});

      expect(fakeSSE.cancelCalls, 1);
    },
  );
}

class _FakeSessionManager extends SessionManager {
  _FakeSessionManager(this._id);

  final String _id;

  @override
  String build() => _id;
}

class _FakeChatSSE extends ChatSSE {
  _FakeChatSSE(this._controller)
    : super(
        apiClient: ApiClient(
          authInterceptor: AuthInterceptor(
            getAccessToken: () async => null,
            getRefreshToken: () async => null,
            saveTokens:
                ({required accessToken, required refreshToken}) async {},
            onAuthFailure: () async {},
            onRefresh: (_) async => null,
            replay: (_) async => throw UnimplementedError(),
          ),
          dio: Dio(),
        ),
      );

  final StreamController<SSEChatEvent> _controller;
  var cancelCalls = 0;

  @override
  Stream<SSEChatEvent> streamChat({
    required String sessionId,
    required String message,
  }) {
    return _controller.stream;
  }

  @override
  void cancel() {
    cancelCalls++;
  }
}

class _FakeChatRepository implements IChatRepository {
  List<MessageModel> history = [];

  @override
  Future<String> sendMessage({
    required String sessionId,
    required String message,
  }) async {
    return '';
  }

  @override
  Future<List<MessageModel>> getHistory(String sessionId) async {
    return history;
  }

  @override
  Future<void> clearHistory(String sessionId) async {
    // no-op
  }
}
