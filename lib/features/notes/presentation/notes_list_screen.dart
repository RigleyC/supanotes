import 'package:cue/cue.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/core/router/app_routes.dart';
import 'package:supanotes/core/sync/sync_service.dart';
import 'package:supanotes/features/notes/data/notes_repository.dart';
import 'package:supanotes/features/notes/domain/note_model.dart';
import 'package:supanotes/features/notes/presentation/controllers/notes_providers.dart';
import 'package:supanotes/features/notes/presentation/widgets/brain_dump_tile.dart';
import 'package:supanotes/features/notes/presentation/widgets/notes_grid_view.dart';
import 'package:supanotes/features/notes/presentation/widgets/notes_list_view.dart';
import 'package:supanotes/features/notes/presentation/widgets/notes_more_menu.dart';
import 'package:supanotes/features/notes/presentation/widgets/daily_brief_panel.dart';
import 'package:supanotes/features/notes/presentation/widgets/pull_down_brief_panel.dart';
import 'package:supanotes/features/notes/presentation/widgets/section_title.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/widgets/app_error_view.dart';
import 'package:supanotes/shared/widgets/app_snackbar.dart';
import 'package:supanotes/shared/widgets/offline_indicator.dart';
import 'package:supanotes/features/routines/presentation/controllers/daily_brief_provider.dart';

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
  static const double _fabClearance = 80;
  _NotesViewMode _viewMode = _NotesViewMode.list;
  final ValueNotifier<double> _panelProgress = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    ref.read(dailyBriefProvider);
  }

  @override
  void dispose() {
    _panelProgress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notesAsync = ref.watch(activeNotesProvider);
    final favoritesOnly = ref.watch(favoritesFilterProvider);

    final headerSlivers = [
      const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
      SliverToBoxAdapter(
        child: BrainDumpTile(
          title: _Strings.brainDump,
          onTap: () => context.push(AppRoutes.inbox),
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxl)),
      const SliverToBoxAdapter(child: SectionTitle(title: _Strings.notesSection)),
    ];

    final body = notesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) =>
          AppErrorView(title: _Strings.errorTitle, subtitle: e.toString()),
      data: (notes) {
        final visibleNotes = favoritesOnly
            ? notes.where((n) => n.favorite).toList()
            : notes;

        return Stack(
          children: [
            PullDownBriefPanel(
              background: const DailyBriefPanel(),
              onProgressChanged: (progress) => _panelProgress.value = progress,
              builder: (context, scrollController) {
                return Cue.onChange(
                  value: _viewMode,
                  motion: .smooth(),
                  acts: [.fadeIn()],
                  child: _viewMode == _NotesViewMode.grid
                      ? NotesGridView(
                          key: const ValueKey('grid'),
                          controller: scrollController,
                          notes: visibleNotes,
                          headerSlivers: headerSlivers,
                          onTap: _openNote,
                          onDelete: _deleteNote,
                          onToggleFavorite: _toggleFavorite,
                        )
                      : NotesListView(
                          key: const ValueKey('list'),
                          controller: scrollController,
                          notes: visibleNotes,
                          headerSlivers: headerSlivers,
                          onTap: _openNote,
                          onDelete: _deleteNote,
                          onToggleFavorite: _toggleFavorite,
                        ),
                );
              },
            ),
            Positioned(
              left: AppSpacing.md,
              right: AppSpacing.md,
              bottom: _fabClearance,
              child: const OfflineIndicator(floating: true),
            ),
          ],
        );
      },
    );

    return ValueListenableBuilder<double>(
      valueListenable: _panelProgress,
      builder: (context, progress, _) {
        final easedProgress = Curves.easeOut.transform(progress.clamp(0, 1));
        final appBarColor = Color.lerp(
          Colors.transparent,
          Colors.black,
          easedProgress,
        )!;
        final iconColor = Color.lerp(
          Colors.black,
          Colors.white,
          easedProgress,
        )!;

        return Scaffold(
          appBar: AppBar(
            backgroundColor: appBarColor,
            foregroundColor: iconColor,
            surfaceTintColor: Colors.transparent,
            shadowColor: Colors.transparent,
            animateColor: false,
            elevation: 0,
            actions: [
              _ViewModeToggle(
                viewMode: _viewMode,
                onToggle: _toggleViewMode,
                color: iconColor,
              ),
              IconButton(
                icon: Icon(Icons.search, color: iconColor),
                onPressed: () => context.push(AppRoutes.search),
              ),
              NotesMoreMenu(
                favoritesOnly: favoritesOnly,
                onToggleFavorites: () =>
                    ref.read(favoritesFilterProvider.notifier).toggle(),
                onSync: () => ref.read(syncServiceProvider).sync(),
                onOpenSettings: () => context.push(AppRoutes.settings),
                onLogout: () =>
                    ref.read(authControllerProvider.notifier).logout(),
              ),
            ],
          ),
          body: body,
          floatingActionButton: FloatingActionButton(
            onPressed: () => _openNewNote(context),
            shape: const CircleBorder(),
            child: const Icon(Icons.edit_outlined, size: 22),
          ),
        );
      },
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

class _ViewModeToggle extends StatelessWidget {
  const _ViewModeToggle({
    required this.viewMode,
    required this.onToggle,
    required this.color,
  });

  final _NotesViewMode viewMode;
  final VoidCallback onToggle;
  final Color color;

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
          color: color,
        ),
        onPressed: onToggle,
      ),
    );
  }
}
