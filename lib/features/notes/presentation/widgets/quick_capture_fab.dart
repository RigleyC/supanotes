import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/notes_repository.dart';

class QuickCaptureFAB extends ConsumerWidget {
  const QuickCaptureFAB({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FloatingActionButton.extended(
      onPressed: () => _createAndNavigate(context, ref),
      icon: const Icon(Icons.add),
      label: const Text('Nova nota'),
    );
  }

  Future<void> _createAndNavigate(BuildContext context, WidgetRef ref) async {
    final note = await ref.read(notesRepositoryProvider).createNote();
    if (!context.mounted) return;
    context.push('/notes/${note.id}');
  }
}
