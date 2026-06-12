import 'package:cue/cue.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/core/router/app_routes.dart';
import 'package:supanotes/core/sync/sync_state.dart';
import 'package:supanotes/features/notes/data/notes_repository.dart';
import 'package:supanotes/features/notes/domain/note_model.dart';
import 'package:supanotes/features/notes/presentation/controllers/notes_providers.dart';
import 'package:supanotes/features/notes/presentation/widgets/brain_dump_tile.dart';
import 'package:supanotes/features/notes/presentation/widgets/notes_grid_view.dart';
import 'package:supanotes/features/notes/presentation/widgets/notes_list_view.dart';
import 'package:supanotes/features/notes/presentation/widgets/notes_more_menu.dart';
import 'package:supanotes/features/notes/presentation/widgets/section_title.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/widgets/app_error_view.dart';
import 'package:supanotes/shared/widgets/app_snackbar.dart';
import 'package:supanotes/shared/widgets/offline_indicator.dart';

class _Strings {
  _Strings._();
  static const String brainDump = 'Brain Dump';
  static const String notesSection = 'Notas';
  static const String noteDeleted = 'Nota movida para a lixeira';
  static const String errorTitle = 'Erro ao carregar as notas';
}

enum _NotesViewMode { list, grid }

class NotesListScreen extends ConsumerStatefulWidget {
  const NotesListScreen({super.key});

  @override
  ConsumerState<NotesListScreen> createState() => _NotesListScreenState();
}

class _NotesListScreenState extends ConsumerState<NotesListScreen> {
  _NotesViewMode _viewMode = _NotesViewMode.list;

  @override
  Widget build(BuildContext context) {
    final notesAsync = ref.watch(activeNotesProvider);

    final headerSlivers = [
      const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
      SliverToBoxAdapter(
        child: BrainDumpTile(
          title: _Strings.brainDump,
          onTap: () => context.push(AppRoutes.inbox),
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxl)),
      const SliverToBoxAdapter(
        child: SectionTitle(title: _Strings.notesSection),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        actions: [
          _ViewModeToggle(viewMode: _viewMode, onToggle: _toggleViewMode),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => context.push(AppRoutes.search),
          ),
          //Remover daqui a opcao de exibir so favoritos.
          NotesMoreMenu(
            onOpenSettings: () => context.push(AppRoutes.settings),
            onLogout: () => ref.read(authControllerProvider.notifier).logout(),
          ),
        ],
      ),
      body: notesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            AppErrorView(title: _Strings.errorTitle, subtitle: e.toString()),
        data: (notes) {
          return Cue.onChange(
            value: _viewMode,
            motion: .smooth(),
            acts: [.fadeIn()],
            child: _viewMode == _NotesViewMode.grid
                ? NotesGridView(
                    key: const ValueKey('grid'),
                    notes: notes.toList(),
                    headerSlivers: headerSlivers,
                    onTap: _openNote,
                    onDelete: _deleteNote,
                    onToggleFavorite: _toggleFavorite,
                  )
                : NotesListView(
                    key: const ValueKey('list'),
                    notes: notes.toList(),
                    headerSlivers: headerSlivers,
                    onTap: _openNote,
                    onDelete: _deleteNote,
                    onToggleFavorite: _toggleFavorite,
                  ),
          );
        },
      ),
      bottomSheet: const _OfflineStatusBottomSheet(),
      floatingActionButton: FloatingActionButton(
        
        onPressed: () => _openNewNote(context),
        shape: const CircleBorder(),
        child: const Icon(Icons.edit_outlined, size: 22),
      ),
    );
  }

  void _openNote(NoteModel note) => context.push(AppRoutes.note(note.id));

  Future<void> _openNewNote(BuildContext context) async {
    final id = const Uuid().v4();
    await ref.read(notesRepositoryProvider).createLocalNote(id: id);
    if (!context.mounted) return;
    context.push(AppRoutes.note(id));
  }

  void _deleteNote(NoteModel note) {
    ref.read(notesRepositoryProvider).softDelete(note.id);
    if (!mounted) return;
    AppMessenger.showSuccess(context, _Strings.noteDeleted);
  }

  void _toggleFavorite(NoteModel note) {
    ref.read(notesRepositoryProvider).toggleFavorite(note.id);
  }

  void _toggleViewMode() {
    setState(() {
      _viewMode = _viewMode == _NotesViewMode.grid
          ? _NotesViewMode.list
          : _NotesViewMode.grid;
    });
  }
}

class _OfflineStatusBottomSheet extends ConsumerWidget {
  const _OfflineStatusBottomSheet();

  static const double _fabClearance = 80;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncStateProvider.select((state) => state.status));
    if (status == SyncStatus.idle || status == SyncStatus.syncing) {
      return const SizedBox.shrink();
    }

    return const SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          _fabClearance,
        ),
        child: OfflineIndicator(floating: true),
      ),
    );
  }
}

class _ViewModeToggle extends StatelessWidget {
  const _ViewModeToggle({required this.viewMode, required this.onToggle});

  final _NotesViewMode viewMode;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Cue.onToggle(
      toggled: viewMode == _NotesViewMode.grid,
      motion: .snappy(),
      acts: [.rotate(to: 90)],
      child: IconButton(
        icon: Icon(
          viewMode == _NotesViewMode.grid
              ? Icons.list_rounded
              : Icons.grid_view_rounded,
        ),
        onPressed: onToggle,
      ),
    );
  }
}
