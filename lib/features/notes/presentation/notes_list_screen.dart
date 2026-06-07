import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/core/sync/sync_service.dart';
import 'package:supanotes/features/notes/data/notes_repository.dart';
import 'package:supanotes/features/notes/domain/note_model.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/widgets/empty_state.dart';

final notesListProvider = StreamProvider<List<NoteModel>>((ref) {
  final repo = ref.watch(notesRepositoryProvider);
  return repo.watchNotes();
});

final inboxProvider = StreamProvider<NoteModel?>((ref) {
  final repo = ref.watch(notesRepositoryProvider);
  return repo.watchInbox();
});

class NotesListScreen extends ConsumerStatefulWidget {
  const NotesListScreen({super.key});

  @override
  ConsumerState<NotesListScreen> createState() => _NotesListScreenState();
}

class _NotesListScreenState extends ConsumerState<NotesListScreen> {
  bool _favoritesOnly = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final notesAsync = ref.watch(notesListProvider);
    final inboxAsync = ref.watch(inboxProvider);

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: scheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: AppSpacing.md,
        toolbarHeight: 56,
        title: const SizedBox.shrink(),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.surfaceContainerHighest,
              ),
              child: IconButton(
                icon: Icon(
                  Icons.more_horiz,
                  color: scheme.onSurfaceVariant,
                ),
                onPressed: () => _showMoreMenu(context),
              ),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(syncServiceProvider).sync(),
        child: notesAsync.when(
          data: (notes) {
            final inbox = inboxAsync.asData?.value;
            final visibleNotes = _favoritesOnly
                ? notes.where((n) => n.favorite).toList()
                : notes;

            if (inbox == null && visibleNotes.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.6,
                    child: const EmptyState(
                      icon: Icons.edit_note,
                      title: 'Nenhuma nota',
                      subtitle:
                          'Toque no botão + para criar sua primeira nota',
                    ),
                  ),
                ],
              );
            }

            final hasInboxContent =
                inbox != null && (inbox.title != null || inbox.content.isNotEmpty);

            return ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.lg,
              ),
              itemCount: (inbox != null && hasInboxContent ? 1 : 0) +
                  visibleNotes.length,
              itemBuilder: (context, index) {
                if (inbox != null && hasInboxContent && index == 0) {
                  return _NoteRow(
                    note: inbox,
                    isInbox: true,
                    textTheme: textTheme,
                    scheme: scheme,
                    onTap: () => context.push('/notes/${inbox.id}'),
                    onDelete: () => _deleteNote(inbox.id),
                    onToggleFavorite: () =>
                        _toggleFavorite(inbox.id, inbox.favorite),
                  );
                }
                final noteIndex =
                    (inbox != null && hasInboxContent) ? index - 1 : index;
                final note = visibleNotes[noteIndex];
                return _NoteRow(
                  note: note,
                  textTheme: textTheme,
                  scheme: scheme,
                  onTap: () => context.push('/notes/${note.id}'),
                  onDelete: () => _deleteNote(note.id),
                  onToggleFavorite: () =>
                      _toggleFavorite(note.id, note.favorite),
                );
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => EmptyState(
            icon: Icons.error_outline,
            title: 'Erro ao carregar',
            subtitle: err.toString(),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _createNote(context),
        backgroundColor: scheme.onSurface,
        foregroundColor: scheme.surface,
        elevation: 2,
        shape: const CircleBorder(),
        child: const Icon(Icons.edit_outlined, size: 22),
      ),
    );
  }

  Future<void> _createNote(BuildContext context) async {
    final note = await ref.read(notesRepositoryProvider).createNote();
    if (!context.mounted) return;
    context.push('/notes/${note.id}');
  }

  Future<void> _deleteNote(String id) async {
    await ref.read(notesRepositoryProvider).softDelete(id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Nota deletada')),
    );
  }

  Future<void> _toggleFavorite(String id, bool current) async {
    try {
      await ref
          .read(notesRepositoryProvider)
          .updateNote(id, favorite: !current);
    } catch (_) {}
  }

  Future<void> _showMoreMenu(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        box.localToGlobal(Offset(box.size.width - 48, 56), ancestor: overlay),
        box.localToGlobal(Offset(box.size.width, 56 + 200), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );
    final selection = await showMenu<_MenuAction>(
      context: context,
      position: position,
      items: [
        CheckedPopupMenuItem<_MenuAction>(
          value: _MenuAction.favoritesOnly,
          checked: _favoritesOnly,
          child: const Text('Apenas favoritos'),
        ),
        const PopupMenuItem<_MenuAction>(
          value: _MenuAction.sync,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.sync),
            title: Text('Sincronizar agora'),
          ),
        ),
        const PopupMenuItem<_MenuAction>(
          value: _MenuAction.logout,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.logout),
            title: Text('Sair'),
          ),
        ),
      ],
    );
    if (selection == null || !mounted) return;
    switch (selection) {
      case _MenuAction.favoritesOnly:
        setState(() => _favoritesOnly = !_favoritesOnly);
      case _MenuAction.sync:
        await ref.read(syncServiceProvider).sync();
      case _MenuAction.logout:
        await ref.read(authControllerProvider.notifier).logout();
    }
  }
}

enum _MenuAction { favoritesOnly, sync, logout }

class _NoteRow extends StatelessWidget {
  const _NoteRow({
    required this.note,
    required this.onTap,
    required this.onDelete,
    required this.onToggleFavorite,
    required this.textTheme,
    required this.scheme,
    this.isInbox = false,
  });

  final NoteModel note;
  final bool isInbox;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onToggleFavorite;
  final TextTheme textTheme;
  final ColorScheme scheme;

  String get _displayTitle {
    final trimmed = note.title?.trim();
    if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    return isInbox ? 'Rascunho' : 'Sem título';
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: () => _showActions(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Text(
          _displayTitle,
          style: textTheme.titleMedium?.copyWith(
            color: scheme.onSurface,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  void _showActions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(
                  note.favorite ? Icons.star : Icons.star_border,
                ),
                title: Text(
                  note.favorite ? 'Desfavoritar' : 'Favoritar',
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  onToggleFavorite();
                },
              ),
              if (!isInbox)
                ListTile(
                  leading: const Icon(Icons.folder_open),
                  title: const Text('Mover contexto'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                  },
                ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Deletar'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _confirmDelete(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Deletar nota'),
          content: const Text('Tem certeza que deseja deletar esta nota?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                onDelete();
              },
              child: const Text('Deletar'),
            ),
          ],
        );
      },
    );
  }
}
