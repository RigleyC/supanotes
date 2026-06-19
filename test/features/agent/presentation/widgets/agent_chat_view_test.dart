import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/agent/domain/message_model.dart';
import 'package:supanotes/features/agent/presentation/controllers/chat_controller.dart';
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
          actions: const [],
          loaded: true,
          streaming: false,
          onSend: (_) {},
          errorMessage: null,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Comece uma conversa'), findsNothing);
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
          actions: const [],
          loaded: true,
          streaming: false,
          onSend: (_) {},
          errorMessage: null,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Oi'), findsOneWidget);
    expect(find.text('Ol\u00e1'), findsOneWidget);
  });

  testWidgets('shows loading indicator while not loaded', (tester) async {
    await tester.pumpWidget(
      wrap(
        AgentChatView(
          messages: const [],
          actions: const [],
          loaded: false,
          streaming: false,
          onSend: (_) {},
          errorMessage: null,
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('shows inline error with retry action', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      wrap(
        AgentChatView(
          messages: const [],
          actions: const [],
          loaded: true,
          streaming: false,
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

  testWidgets('confirmation action card calls approve and cancel callbacks', (
    tester,
  ) async {
    final resolved = <bool>[];
    await tester.pumpWidget(
      wrap(
        AgentChatView(
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
          loaded: true,
          streaming: false,
          onSend: (_) {},
          onResolveConfirmation: (_, {required approved}) =>
              resolved.add(approved),
          errorMessage: null,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Confirmação necessária'), findsOneWidget);
    expect(find.text('Atualizando notas'), findsOneWidget);

    await tester.tap(find.text('Confirmar'));
    await tester.pump();
    await tester.tap(find.text('Cancelar'));
    await tester.pump();

    expect(resolved, [true, false]);
  });
}
