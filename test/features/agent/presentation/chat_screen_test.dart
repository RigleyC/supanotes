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

  @override
  ChatState build() => initialState;

  @override
  Future<void> sendMessage(String content) async {
    sent.add(content);
  }
}

void main() {
  testWidgets('chat screen renders package chat view and sends through controller', (tester) async {
    final controller = _TestChatController(
      (
        loaded: true,
        streaming: false,
        error: null,
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

    expect(find.text('Chat'), findsOneWidget);
    expect(find.text('Como posso ajudar?'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Ajude com minhas notas');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    expect(controller.sent, ['Ajude com minhas notas']);
  });
}
