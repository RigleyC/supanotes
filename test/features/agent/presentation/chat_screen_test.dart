import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/agent/domain/message_model.dart';
import 'package:supanotes/features/agent/presentation/chat_screen.dart';
import 'package:supanotes/features/agent/presentation/controllers/chat_controller.dart';
import 'package:supanotes/shared/theme/app_theme.dart';

class _TestChatController extends ChatController {
  _TestChatController(this.initialState);

  final ChatState initialState;
  final sent = <String>[];
  final resolvedConfirmations = <(String, bool)>[];

  @override
  Future<ChatState> build() async => initialState;

  @override
  Future<void> sendMessage(String content) async {
    sent.add(content);
  }

  @override
  Future<void> resolveToolConfirmation(
    String confirmationId, {
    required bool approved,
  }) async {
    resolvedConfirmations.add((confirmationId, approved));
  }
}

void main() {
  testWidgets('chat screen renders agent chat view and sends through controller', (tester) async {
    final controller = _TestChatController(
      chatState(
        isStreaming: false,
        messages: [
          MessageModel(
            id: 'assistant-1',
            sessionId: 'session-1',
            role: MessageRole.assistant,
            content: 'Como posso ajudar?',
            createdAt: DateTime.utc(2026, 6, 12, 14, 30),
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatControllerProvider.overrideWith(() => controller),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const ChatScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Como posso ajudar?'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
  });

  testWidgets('chat screen resolves confirmation through controller', (tester) async {
    final controller = _TestChatController(
      chatState(
        messages: const [],
        actions: [
          (
            id: 'action-1',
            name: 'update_note',
            label: 'Atualizando notas',
            status: ChatToolActionStatus.confirmationRequired,
            message: null,
            confirmationId: 'confirmation-1',
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatControllerProvider.overrideWith(() => controller),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const ChatScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Confirmação necessária'), findsOneWidget);
    expect(find.text('Atualizando notas'), findsOneWidget);

    await tester.tap(find.text('Confirmar'));
    await tester.pump();

    expect(controller.resolvedConfirmations, [('confirmation-1', true)]);
  });
}
