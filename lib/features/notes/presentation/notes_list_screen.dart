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
  bool _isPanelOpen = false;

  @override
  void initState() {
    super.initState();
    ref.read(dailyBriefProvider);
  }

  @override
  Widget build(BuildContext context) {
    final notesAsync = ref.watch(activeNotesProvider);
    final favoritesOnly = ref.watch(favoritesFilterProvider);

    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(
        begin: Colors.transparent,
        end: _isPanelOpen ? Colors.black : Colors.transparent,
      ),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      child: notesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            AppErrorView(title: _Strings.errorTitle, subtitle: e.toString()),
        data: (notes) {
          final visibleNotes = favoritesOnly
              ? notes.where((n) => n.favorite).toList()
              : notes;
          final headerSlivers = _buildHeaderSlivers();

          return Stack(
            children: [
              PullDownBriefPanel(
                onOpenChanged: (open) => setState(() => _isPanelOpen = open),
                child: Cue.onChange(
                  value: _viewMode,
                  motion: .smooth(),
                  acts: [.fadeIn()],
                  child: _viewMode == _NotesViewMode.grid
                      ? NotesGridView(
                          key: const ValueKey('grid'),
                          notes: visibleNotes,
                          headerSlivers: headerSlivers,
                          onTap: _openNote,
                          onDelete: _deleteNote,
                          onToggleFavorite: _toggleFavorite,
                        )
                      : NotesListView(
                          key: const ValueKey('list'),
                          notes: visibleNotes,
                          headerSlivers: headerSlivers,
                          onTap: _openNote,
                          onDelete: _deleteNote,
                          onToggleFavorite: _toggleFavorite,
                        ),
                ),
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
      ),
      builder: (context, animatedBgColor, child) {
        final isDark = animatedBgColor!.computeLuminance() < 0.15;
        final iconColor = isDark ? Colors.white : Colors.black;

        return Scaffold(
          appBar: AppBar(
            backgroundColor: animatedBgColor,
            foregroundColor: iconColor,
            surfaceTintColor: animatedBgColor,
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
                onLogout: () =>
                    ref.read(authControllerProvider.notifier).logout(),
              ),
            ],
          ),
          body: child,
          floatingActionButton: FloatingActionButton(
            onPressed: () => _openNewNote(context),
            shape: const CircleBorder(),
            child: const Icon(Icons.edit_outlined, size: 22),
          ),
        );
      },
    );
  }

  //Isso aqui pode ficar fixo na pagina sem rebuildar, podemos rebuildar apenas a visualização das notas, alem de que nao precisa ta extraindo aqui embaixo
  List<Widget> _buildHeaderSlivers() => [
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

  void _openNote(NoteModel note) => context.push(AppRoutes.note(note.id));

  void _openNewNote(BuildContext context) {
    final id = const Uuid().v4();
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
