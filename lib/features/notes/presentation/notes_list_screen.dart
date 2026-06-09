import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/core/router/app_routes.dart';
import 'package:supanotes/core/sync/sync_service.dart';
import 'package:supanotes/shared/widgets/offline_indicator.dart';
import 'package:supanotes/features/notes/data/notes_repository.dart';
import 'package:supanotes/features/notes/domain/note_model.dart';
import 'package:supanotes/features/notes/presentation/controllers/notes_providers.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/widgets/app_card.dart';
import 'package:supanotes/shared/widgets/app_error_view.dart';
import 'package:supanotes/shared/widgets/app_snackbar.dart';
import 'package:supanotes/shared/widgets/app_status_chip.dart';
import 'package:supanotes/shared/widgets/confirm_dialog.dart';
import 'package:supanotes/shared/widgets/empty_state.dart';

class NotesListScreen extends ConsumerStatefulWidget {
  const NotesListScreen({super.key});

  @override
  ConsumerState<NotesListScreen> createState() => _NotesListScreenState();
}

class _NotesListScreenState extends ConsumerState<NotesListScreen> {
  @override
  Widget build(BuildContext context) {

    // se nao tiver notas não precisa exibir nada na listagem, mantenha apenas as sections
    final notes = ref.watch(activeNotesProvider);

    return Scaffold(
      appBar: AppBar(
        // a appbar pode ser customizada como transparent desde o themedata
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => context.push(AppRoutes.search),
          ),
          IconButton(
            icon: const Icon(Icons.more_horiz),
            onPressed: () => _showMoreMenu(
                context), // Esse menu deve ser um popup menu comum, extraido pra um widget/componente
          ),
        ],
      ),
      body: Column(children: [
        SizedBox(height: 24),
        ListTile(
          //esse tambem vira um componente
          // leading: const Icon(Icons.), coloca o icone de lixeira aqui
          title: const Text('Brain Dump'),
          onTap: () => context.push(AppRoutes.inbox),
        ),
        SizedBox(height: 40),
        ListTile(
          // esse aqui pode ser um componente/widget tambem, algo como sectiontitle
          // leading: const Icon(Icons.), coloca o icone de lixeira aqui
          title: const Text('Notas'),
        ),
        ListView.builder(
          shrinkWrap: true,
          itemCount: notes.asData?.value.length ?? 0,
          itemBuilder: (context, index) {
            final note = notes.asData!.value[index];
            return Dismissible(
              //adicionar confirmação pra deletar, um dialog, extrai pra widget/componente, acho que seria o noteRow
              key: Key(note.id),
              onDismissed: (_) => _deleteNote(note.id),
              child: ListTile(
                title: Text(note.title ?? 'Sem título'),
                onTap: () => context.push(AppRoutes.note(note.id)),
              ),
            );
          },
        ),
      ]),
      floatingActionButton: FloatingActionButton(
        // adicionar esse botao como componente la em button.dart
        onPressed: () => _createNote(context),
        shape: const CircleBorder(),
        child: const Icon(Icons.edit_outlined, size: 22),
      ),
    );

    /*    final scheme = Theme.of(context).colorScheme;
    final inboxAsync = ref.watch(inboxProvider);
    final notesAsync = ref.watch(activeNotesProvider);
    final favoritesOnly = ref.watch(favoritesFilterProvider);

    if (inboxAsync.isLoading || notesAsync.isLoading) {
      return Scaffold(
        backgroundColor: scheme.surface,
        appBar: _buildAppBar(scheme),
        body: Column(
          children: [
            const OfflineIndicator(),
            const Expanded(
              child: Center(child: CircularProgressIndicator()),
            ),
          ],
        ),
      );
    }

    final error = inboxAsync.hasError
        ? inboxAsync.error
        : notesAsync.hasError
            ? notesAsync.error
            : null;
    if (error != null) {
      return Scaffold(
        backgroundColor: scheme.surface,
        appBar: _buildAppBar(scheme),
        body: Column(
          children: [
            const OfflineIndicator(),
            Expanded(
              child: AppErrorView(
                title: 'Erro ao carregar',
                subtitle: error.toString(),
              ),
            ),
          ],
        ),
      );
    }

    final inbox = inboxAsync.asData?.value;
    final notes = notesAsync.asData?.value ?? [];
    final visibleNotes =
        favoritesOnly ? notes.where((n) => n.favorite).toList() : notes;

    if (inbox == null && visibleNotes.isEmpty) {
      return Scaffold(
        backgroundColor: scheme.surface,
        appBar: _buildAppBar(scheme),
        body: Column(
          children: [
            const OfflineIndicator(),
            Expanded(
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.6,
                    child: const EmptyState(
                      icon: Icons.edit_note,
                      title: 'Nenhuma nota',
                      subtitle: 'Toque no botão + para criar sua primeira nota',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        floatingActionButton: _buildFab(scheme),
      );
    }

    final hasInboxContent =
        inbox != null && (inbox.title != null || inbox.content.isNotEmpty);

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: _buildAppBar(scheme),
      body: Column(
        children: [
          const OfflineIndicator(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.read(syncServiceProvider).sync(),
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.lg,
                ),
                itemCount: (inbox != null && hasInboxContent ? 1 : 0) +
                    visibleNotes.length,
                itemBuilder: (context, index) {
                  if (inbox != null && hasInboxContent && index == 0) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: _NoteRow(
                        note: inbox,
                        isInbox: true,
                        onTap: () => context.push(AppRoutes.note(inbox.id)),
                        onDelete: () => _deleteNote(inbox.id),
                        onToggleFavorite: () => ref
                            .read(notesRepositoryProvider)
                            .toggleFavorite(inbox.id),
                      ),
                    );
                  }
                  final noteIndex =
                      (inbox != null && hasInboxContent) ? index - 1 : index;
                  final note = visibleNotes[noteIndex];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: _NoteRow(
                      note: note,
                      onTap: () => context.push(AppRoutes.note(note.id)),
                      onDelete: () => _deleteNote(note.id),
                      onToggleFavorite: () => ref
                          .read(notesRepositoryProvider)
                          .toggleFavorite(note.id),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: _buildFab(scheme),
    ); */
  }

  PreferredSizeWidget _buildAppBar(ColorScheme scheme) {
    return AppBar(
      backgroundColor: scheme.surface,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleSpacing: AppSpacing.md,
      toolbarHeight: 56,
      title: const SizedBox.shrink(),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: AppSpacing.sm),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.surfaceContainerHighest,
                ),
                child: IconButton(
                  icon: Icon(
                    Icons.search,
                    color: scheme.onSurfaceVariant,
                  ),
                  onPressed: () => context.push(AppRoutes.search),
                ),
              ),
              const SizedBox(width: 8),
              Container(
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
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFab(ColorScheme scheme) {
    return FloatingActionButton(
      onPressed: () => _createNote(context),
      backgroundColor: scheme.onSurface,
      foregroundColor: scheme.surface,
      elevation: 2,
      shape: const CircleBorder(),
      child: const Icon(Icons.edit_outlined, size: 22),
    );
  }

  Future<void> _createNote(BuildContext context) async {
    final note = await ref.read(notesRepositoryProvider).createNote();
    if (!context.mounted) return;
    context.push(AppRoutes.note(note.id));
  }

  Future<void> _deleteNote(String id) async {
    await ref.read(notesRepositoryProvider).softDelete(id);
    if (!mounted) return;
    AppMessenger.showSuccess(context, 'Nota deletada');
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
    final favoritesOnly = ref.read(favoritesFilterProvider);
    final selection = await showMenu<_MenuAction>(
      context: context,
      position: position,
      items: [
        CheckedPopupMenuItem<_MenuAction>(
          value: _MenuAction.favoritesOnly,
          checked: favoritesOnly,
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
        ref.read(favoritesFilterProvider.notifier).toggle();
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
    this.isInbox = false,
  });

  final NoteModel note;
  final bool isInbox;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onToggleFavorite;

  String get _displayTitle {
    final trimmed = note.title?.trim();
    if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    return isInbox ? 'Rascunho' : 'Sem título';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return AppCard(
      onTap: onTap,
      onLongPress: () => _showActions(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _displayTitle,
                  style: textTheme.titleMedium?.copyWith(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (note.favorite)
                Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.sm),
                  child: Icon(
                    Icons.star,
                    size: 18,
                    color: scheme.tertiary,
                  ),
                ),
            ],
          ),
          if (note.contextId != null) ...[
            const SizedBox(height: AppSpacing.xs),
            AppStatusChip(label: note.contextId!),
          ],
        ],
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

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: 'Deletar nota',
      message: 'Tem certeza que deseja deletar esta nota?',
      confirmLabel: 'Deletar',
      destructive: true,
    );
    if (confirmed) {
      onDelete();
    }
  }
}
