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
import 'package:supanotes/features/agent/domain/tool_confirmation.dart';
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

  test('tool_started appends a running action', () async {
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
    expect(data.actions.single.name, 'search_notes');
    expect(data.actions.single.label, 'Buscando notas');
    expect(data.actions.single.status, ChatToolActionStatus.running);
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
    expect(state.hasError, isTrue);
    expect(state.error, 'Stream failed');
    final data = state.value;
    expect(data, isNotNull);
    expect(data!.isStreaming, isFalse);
  });

  test('confirmation_required stores confirmation id', () async {
    final container = createContainer();
    final controller = container.read(chatControllerProvider.notifier);

    controller.sendMessage('update note');
    await Future(() {});

    streamController.add(
      SSEChatEvent(
        type: 'confirmation_required',
        payload: {
          'confirmation_id': 'confirmation-1',
          'tool_name': 'update_note',
          'label': 'Atualizando notas',
        },
      ),
    );

    await Future(() {});

    final state = container.read(chatControllerProvider);
    final action = state.value!.actions.single;
    expect(action.status, ChatToolActionStatus.confirmationRequired);
    expect(action.confirmationId, 'confirmation-1');
    expect(action.name, 'update_note');
    expect(action.label, 'Atualizando notas');
  });

  test('resolveToolConfirmation marks approved action and appends result message', () async {
    final container = createContainer();
    fakeRepo.confirmationResponse = ToolConfirmationResolution(
      confirmationId: 'confirmation-1',
      status: ConfirmationStatus.approved,
      message: 'Nota atualizada',
    );
    final controller = container.read(chatControllerProvider.notifier);

    controller.sendMessage('update note');
    await Future(() {});

    streamController.add(
      SSEChatEvent(
        type: 'confirmation_required',
        payload: {
          'confirmation_id': 'confirmation-1',
          'tool_name': 'update_note',
          'label': 'Atualizando notas',
        },
      ),
    );
    await Future(() {});

    await controller.resolveToolConfirmation('confirmation-1', approved: true);
    await Future(() {});

    final data = container.read(chatControllerProvider).value!;
    expect(data.actions.single.status, ChatToolActionStatus.confirmed);
    expect(data.messages.last.role, MessageRole.tool);
    expect(data.messages.last.content, 'Nota atualizada');
  });

  test('resolveToolConfirmation with cancelled marks action and appends message', () async {
    final container = createContainer();
    fakeRepo.confirmationResponse = ToolConfirmationResolution(
      confirmationId: 'confirmation-1',
      status: ConfirmationStatus.cancelled,
      message: 'Ação cancelada.',
    );
    final controller = container.read(chatControllerProvider.notifier);

    controller.sendMessage('update note');
    await Future(() {});

    streamController.add(
      SSEChatEvent(
        type: 'confirmation_required',
        payload: {
          'confirmation_id': 'confirmation-1',
          'tool_name': 'update_note',
          'label': 'Atualizando notas',
        },
      ),
    );
    await Future(() {});

    await controller.resolveToolConfirmation('confirmation-1', approved: false);
    await Future(() {});

    final data = container.read(chatControllerProvider).value!;
    expect(data.actions.single.status, ChatToolActionStatus.cancelled);
    expect(data.messages.last.content, 'Ação cancelada.');
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
        apiClient: ApiClient.test(
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
  ToolConfirmationResolution? confirmationResponse;

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

  @override
  Future<ToolConfirmationResolution> resolveToolConfirmation({
    required String confirmationId,
    required bool approved,
  }) async {
    return confirmationResponse ??
        ToolConfirmationResolution(
          confirmationId: confirmationId,
          status: approved
              ? ConfirmationStatus.approved
              : ConfirmationStatus.cancelled,
          message: approved ? 'Executado' : 'Ação cancelada.',
        );
  }
}
