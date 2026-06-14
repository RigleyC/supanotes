import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/agent/domain/message_model.dart';
import 'package:supanotes/features/agent/presentation/widgets/agent_chat_view.dart';
import 'package:supanotes/shared/theme/app_theme.dart';

void main() {
  MessageModel message({
    required String id,
    required MessageRole role,
    required String content,
  }) {
    return MessageModel(
      id: id,
      sessionId: 'session-1',
      role: role,
      content: content,
      createdAt: DateTime.utc(2026, 6, 12, 14, 30),
    );
  }

  Widget wrap(Widget child) {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(body: child),
    );
  }

  testWidgets('renders empty chat state', (tester) async {
    await tester.pumpWidget(
      wrap(
        AgentChatView(
          messages: const [],
          loaded: true,
          streaming: false,
          onSend: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Comece uma conversa'), findsOneWidget);
    expect(find.text('Pergunte algo ao agent e a resposta aparecer\u00e1 aqui.'), findsOneWidget);
  });

  testWidgets('renders user and assistant text messages', (tester) async {
    await tester.pumpWidget(
      wrap(
        AgentChatView(
          messages: [
            message(id: 'user-1', role: MessageRole.user, content: 'Oi'),
            message(id: 'assistant-1', role: MessageRole.assistant, content: 'Ol\u00e1'),
          ],
          loaded: true,
          streaming: false,
          onSend: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Oi'), findsOneWidget);
    expect(find.text('Ol\u00e1'), findsOneWidget);
  });

  testWidgets('shows typing indicator while waiting for first assistant delta', (tester) async {
    await tester.pumpWidget(
      wrap(
        AgentChatView(
          messages: [
            message(id: 'user-1', role: MessageRole.user, content: 'Resumo?'),
            message(id: 'assistant-1', role: MessageRole.assistant, content: ''),
          ],
          loaded: true,
          streaming: true,
          onSend: (_) {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const ValueKey('agent-chat-typing-indicator')), findsOneWidget);
  });

  testWidgets('sends text through custom composer', (tester) async {
    final sent = <String>[];
    await tester.pumpWidget(
      wrap(
        AgentChatView(
          messages: const [],
          loaded: true,
          streaming: false,
          onSend: sent.add,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(find.byType(TextField), 'Criar resumo');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    expect(sent, ['Criar resumo']);
  });
}
