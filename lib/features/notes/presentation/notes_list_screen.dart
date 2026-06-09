import 'dart:developer' as dev;

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
import 'package:supanotes/features/notes/presentation/controllers/notes_view_mode_provider.dart';
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

class NotesListScreen extends ConsumerStatefulWidget {
  const NotesListScreen({super.key});

  @override
  ConsumerState<NotesListScreen> createState() => _NotesListScreenState();
}

class _NotesListScreenState extends ConsumerState<NotesListScreen> {
  static const double _fabClearance = 80;

  @override
  void initState() {
    super.initState();
    ref.read(dailyBriefProvider);
  }

  @override
  Widget build(BuildContext context) {
    final notesAsync = ref.watch(activeNotesProvider);
    final favoritesOnly = ref.watch(favoritesFilterProvider);
    final viewMode = ref.watch(notesViewModeProvider);

    dev.log(
      '[NotesListScreen] notesAsync: ${notesAsync.runtimeType}, '
      'hasValue=${notesAsync.hasValue}, isLoading=${notesAsync.isLoading}, '
      'notesCount=${notesAsync.hasValue ? (notesAsync.value?.length ?? 0) : 0}',
      name: 'NotesList',
    );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        actions: [
          _ViewModeToggle(
            viewMode: viewMode,
            onToggle: () =>
                ref.read(notesViewModeProvider.notifier).toggle(),
          ),
          IconButton(
            icon: const Icon(Icons.search, color: Colors.black),
            onPressed: () => context.push(AppRoutes.search),
          ),
          NotesMoreMenu(
            favoritesOnly: favoritesOnly,
            onToggleFavorites: () =>
                ref.read(favoritesFilterProvider.notifier).toggle(),
            onSync: () => ref.read(syncServiceProvider).sync(),
            onLogout: () => ref.read(authControllerProvider.notifier).logout(),
          ),
        ],
      ),
      body: notesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AppErrorView(
          title: _Strings.errorTitle,
          subtitle: e.toString(),
        ),
        data: (notes) {
          final visibleNotes = favoritesOnly
              ? notes.where((n) => n.favorite).toList()
              : notes;
          dev.log(
            '[NotesListScreen] Rendering ${visibleNotes.length} notes',
            name: 'NotesList',
          );
          final headerSlivers = _buildHeaderSlivers();

          return Stack(
            children: [
              PullDownBriefPanel(
                child: Cue.onChange(
                  value: viewMode,
                  motion: .smooth(),
                  acts: [.fadeIn(), .slideY(from: 0.06)],
                  child: viewMode == NotesViewMode.grid
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
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openNewNote(context),
        shape: const CircleBorder(),
        child: const Icon(Icons.edit_outlined, size: 22),
      ),
    );
  }

  List<Widget> _buildHeaderSlivers() => [
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
}

class _ViewModeToggle extends StatelessWidget {
  const _ViewModeToggle({
    required this.viewMode,
    required this.onToggle,
  });

  final NotesViewMode viewMode;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Cue.onToggle(
      toggled: viewMode == NotesViewMode.grid,
      motion: .snappy(),
      acts: [.rotate(to: 90)],
      child: IconButton(
        icon: Icon(
          viewMode == NotesViewMode.grid
              ? Icons.list_rounded
              : Icons.grid_view_rounded,
          color: Colors.black,
        ),
        onPressed: onToggle,
      ),
    );
  }
}
