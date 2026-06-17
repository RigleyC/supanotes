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
          activeToolLabel: null,
          errorMessage: null,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Comece uma conversa'), findsOneWidget);
    expect(
      find.text('Pergunte algo ao agente e a resposta aparecer\u00e1 aqui.'),
      findsOneWidget,
    );
  });

  testWidgets('renders user and assistant text messages', (tester) async {
    await tester.pumpWidget(
      wrap(
        AgentChatView(
          messages: [
            message(id: 'user-1', role: MessageRole.user, content: 'Oi'),
            message(
              id: 'assistant-1',
              role: MessageRole.assistant,
              content: 'Ol\u00e1',
            ),
          ],
          loaded: true,
          streaming: false,
          onSend: (_) {},
          activeToolLabel: null,
          errorMessage: null,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Oi'), findsOneWidget);
    expect(find.text('Ol\u00e1'), findsOneWidget);
  });

  testWidgets(
    'shows typing indicator while waiting for first assistant delta',
    (tester) async {
      await tester.pumpWidget(
        wrap(
          AgentChatView(
            messages: [
              message(id: 'user-1', role: MessageRole.user, content: 'Resumo?'),
              message(
                id: 'assistant-1',
                role: MessageRole.assistant,
                content: '',
              ),
            ],
            loaded: true,
            streaming: true,
            onSend: (_) {},
            activeToolLabel: null,
            errorMessage: null,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.byKey(const ValueKey('agent-chat-typing-indicator')),
        findsOneWidget,
      );
    },
  );

  testWidgets('sends text through custom composer', (tester) async {
    final sent = <String>[];
    await tester.pumpWidget(
      wrap(
        AgentChatView(
          messages: const [],
          loaded: true,
          streaming: false,
          onSend: sent.add,
          activeToolLabel: null,
          errorMessage: null,
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

  testWidgets('shows tool activity while streaming', (tester) async {
    await tester.pumpWidget(
      wrap(
        AgentChatView(
          messages: const [],
          loaded: true,
          streaming: true,
          activeToolLabel: 'Buscando notas',
          errorMessage: null,
          onRetry: null,
          onCancel: () {},
          onSend: (_) {},
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Buscando notas'), findsOneWidget);
    expect(find.byTooltip('Cancelar resposta'), findsOneWidget);
  });

  testWidgets('shows thinking status while streaming before tool activity', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        AgentChatView(
          messages: const [],
          loaded: true,
          streaming: true,
          activeToolLabel: null,
          errorMessage: null,
          onRetry: null,
          onCancel: () {},
          onSend: (_) {},
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Pensando...'), findsOneWidget);
    expect(find.byTooltip('Cancelar resposta'), findsOneWidget);
  });

  testWidgets('prompt suggestion chips send the correct prompt', (
    tester,
  ) async {
    final sent = <String>[];
    await tester.pumpWidget(
      wrap(
        AgentChatView(
          messages: const [],
          loaded: true,
          streaming: false,
          activeToolLabel: null,
          errorMessage: null,
          onSend: sent.add,
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Resuma minhas notas recentes'));
    await tester.pump();
    expect(sent, ['Resuma minhas notas recentes']);
  });

  testWidgets('shows inline error with retry action', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      wrap(
        AgentChatView(
          messages: const [],
          loaded: true,
          streaming: false,
          activeToolLabel: null,
          errorMessage: 'Falha no stream',
          onRetry: () => retried = true,
          onCancel: null,
          onSend: (_) {},
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Falha no stream'), findsOneWidget);
    await tester.tap(find.text('Tentar novamente'));
    await tester.pump();
    expect(retried, isTrue);
  });
}
