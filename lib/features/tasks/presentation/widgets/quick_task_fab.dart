import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/features/notes/data/local/notes_local_repository.dart';

import 'task_edit_sheet.dart';

/// `FloatingActionButton` shown on the "Hoje" screen. On tap, resolves
/// the user's inbox note (creating it on first use) and opens the
/// [TaskEditSheet] in create mode. Falls back to a disabled FAB while
/// the inbox is being resolved or if the user is not signed in.
class QuickTaskFAB extends ConsumerStatefulWidget {
  const QuickTaskFAB({super.key});

  @override
  ConsumerState<QuickTaskFAB> createState() => _QuickTaskFABState();
}

class _QuickTaskFABState extends ConsumerState<QuickTaskFAB> {
  bool _opening = false;

  Future<void> _onTap() async {
    if (_opening) return;
    setState(() => _opening = true);
    final notesLocal = ref.read(notesLocalRepositoryProvider);
    String noteId;
    try {
      final inbox = await notesLocal.getOrCreateInboxNote();
      noteId = inbox.id;
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível abrir a inbox. Tente novamente.'),
        ),
      );
      setState(() => _opening = false);
      return;
    }

    if (!mounted) return;
    setState(() => _opening = false);

    await TaskEditSheet.show(context, noteId: noteId);
  }

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      onPressed: _opening ? null : _onTap,
      icon: _opening
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.add),
      label: const Text('Nova tarefa'),
    );
  }
}
