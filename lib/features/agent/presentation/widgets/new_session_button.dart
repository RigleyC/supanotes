import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/shared/widgets/confirm_dialog.dart';

import '../../data/chat_repository.dart';
import '../../domain/session_manager.dart';

/// AppBar action that wipes the current session and rotates to a fresh
/// `session_id` after a confirmation dialog.
///
/// Wires through [SessionManager] so the [ChatController] watching
/// [sessionManagerProvider] reloads history for the new session
/// automatically.
class NewSessionButton extends ConsumerWidget {
  const NewSessionButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      icon: const Icon(Icons.add_comment_outlined),
      tooltip: 'Nova conversa',
      onPressed: () => _onPressed(context, ref),
    );
  }

  Future<void> _onPressed(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showConfirmDialog(
      context,
      title: 'Nova conversa',
      message: 'Iniciar uma nova conversa? O histórico atual será apagado.',
      confirmLabel: 'Nova conversa',
      isDestructive: true,
    );
    if (confirmed != true) return;

    final oldSessionId = ref.read(sessionManagerProvider);
    try {
      await ref.read(chatRepositoryProvider).clearHistory(oldSessionId);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Não foi possível limpar o histórico no servidor.'),
        ),
      );
    }
    ref.read(sessionManagerProvider.notifier).newSession();
  }
}
