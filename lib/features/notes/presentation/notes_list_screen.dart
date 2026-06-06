import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/sync/sync_service.dart';
import '../../../shared/widgets/empty_state.dart';
import '../data/notes_repository.dart';
import '../domain/note_model.dart';
import 'widgets/note_card.dart';
import 'widgets/quick_capture_fab.dart';

/// Reactive stream of notes for the active user.
///
/// Wraps [NotesRepository.watchNotes] in a [StreamProvider] so widgets
/// can `ref.watch` it like any other Riverpod value. Re-emits on every
/// local DB change and on every remote pull.
final notesListProvider = StreamProvider<List<NoteModel>>((ref) {
  final repo = ref.watch(notesRepositoryProvider);
  return repo.watchNotes();
});

class NotesListScreen extends ConsumerWidget {
  const NotesListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notesAsync = ref.watch(notesListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.inbox),
            onPressed: () => context.push('/inbox'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(syncServiceProvider).sync(),
        child: notesAsync.when(
          data: (notes) {
            if (notes.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 120),
                  EmptyState(
                    icon: Icons.note_add_outlined,
                    title: 'Crie sua primeira nota',
                    subtitle: 'Toque no + para começar',
                  ),
                ],
              );
            }
            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              itemCount: notes.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final note = notes[index];
                return DismissibleDeleteWrapper(
                  noteId: note.id,
                  onDelete: () async {
                    await ref.read(notesRepositoryProvider).softDelete(note.id);
                    return true;
                  },
                  child: NoteCard(
                    note: note,
                    onTap: () => context.push('/notes/${note.id}'),
                    onDelete: () => _confirmAndDelete(context, ref, note.id),
                    onToggleFavorite: () => ref
                        .read(notesRepositoryProvider)
                        .toggleFavorite(note.id),
                  ),
                );
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(child: Text('Erro: $err')),
        ),
      ),
      floatingActionButton: const QuickCaptureFAB(),
    );
  }

  Future<void> _confirmAndDelete(
    BuildContext context,
    WidgetRef ref,
    String id,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Apagar nota?'),
          content: const Text(
            'Esta ação pode ser revertida na sincronização.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Apagar'),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      await ref.read(notesRepositoryProvider).softDelete(id);
    }
  }
}
