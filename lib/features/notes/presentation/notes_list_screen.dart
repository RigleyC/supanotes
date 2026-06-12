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
import 'package:supanotes/features/search/presentation/controllers/search_controller.dart';
import 'package:supanotes/features/search/presentation/widgets/search_bar.dart';
import 'package:supanotes/features/search/presentation/widgets/search_error_view.dart';
import 'package:supanotes/features/search/presentation/widgets/search_loading_view.dart';
import 'package:supanotes/features/search/presentation/widgets/search_results_view.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/widgets/app_error_view.dart';
import 'package:supanotes/shared/widgets/app_snackbar.dart';
import 'package:supanotes/shared/widgets/offline_indicator.dart';
import 'package:supanotes/shared/widgets/quick_action_fabs.dart';

class _Strings {
  _Strings._();
  static const String brainDump = 'Brain Dump';
  static const String notesSection = 'Notas';
  static const String noteDeleted = 'Nota movida para a lixeira';
  static const String errorTitle = 'Erro ao carregar as notas';
  static const String newNoteTooltip = 'Criar nota';
  static const String chatTooltip = 'Conversar com o assistente';
  static const String searchTooltip = 'Buscar notas';
  static const String closeSearchTooltip = 'Fechar busca';
  static const String searchHint = 'Buscar notas';

}

enum _NotesViewMode { list, grid }

class NotesListScreen extends ConsumerStatefulWidget {
  const NotesListScreen({super.key});

  @override
  ConsumerState<NotesListScreen> createState() => _NotesListScreenState();
}

class _NotesListScreenState extends ConsumerState<NotesListScreen> {
  _NotesViewMode _viewMode = _NotesViewMode.list;
  bool _isSearching = false;
  String _searchQuery = '';

  void _openSearch() {
    setState(() => _isSearching = true);
  }

  void _closeSearch() {
    setState(() {
      _isSearching = false;
      _searchQuery = '';
    });
  }

  void _onSearchQueryChanged(String query) {
    setState(() => _searchQuery = query.trim());
  }

  @override
  Widget build(BuildContext context) {
    final notesAsync = ref.watch(activeNotesProvider);
    final trimmedSearchQuery = _searchQuery.trim();
    final searchAsync = trimmedSearchQuery.isEmpty
        ? null
        : ref.watch(searchResultsProvider(trimmedSearchQuery));

    final headerSlivers = [
      const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
      if (_isSearching)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              0,
              AppSpacing.md,
              AppSpacing.md,
            ),
            child: SearchInputBar(
              key: const ValueKey('notes-inline-search-field'),
              initialQuery: _searchQuery,
              hintText: _Strings.searchHint,
              onQueryChanged: _onSearchQueryChanged,
            ),
          ),
        ),
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
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            tooltip: _isSearching
                ? _Strings.closeSearchTooltip
                : _Strings.searchTooltip,
            onPressed: _isSearching ? _closeSearch : _openSearch,
          ),
          NotesMoreMenu(
            isListView: _viewMode == _NotesViewMode.list,
            onToggleViewMode: _toggleViewMode,
            onOpenSettings: () => context.push(AppRoutes.settings),
            onLogout: () => ref.read(authControllerProvider.notifier).logout(),
          ),
        ],
      ),
      body: trimmedSearchQuery.isEmpty
          ? notesAsync.when(
              loading: () => _NotesLoadingView(headerSlivers: headerSlivers),
              error: (e, _) =>
                  AppErrorView(title: _Strings.errorTitle, subtitle: e.toString()),
              data: (notes) => _buildNotesBody(notes, headerSlivers),
            )
          : searchAsync!.when(
              loading: () => SearchLoadingView(headerSlivers: headerSlivers),
              error: (e, _) => SearchErrorView(
                headerSlivers: headerSlivers,
                error: e.toString(),
              ),
              data: (results) => SearchResultsView(
                headerSlivers: headerSlivers,
                query: trimmedSearchQuery,
                results: results,
                onTap: (result) => context.push(AppRoutes.note(result.id)),
              ),
            ),
      bottomSheet: const _OfflineStatusBottomSheet(),
      floatingActionButton: QuickActionFabs(
        smallFabKey: const ValueKey('home-chat-fab'),
        smallHeroTag: 'home-chat-fab',
        smallIcon: 'assets/icons/agent.svg',
        smallTooltip: _Strings.chatTooltip,
        onSmallPressed: () => context.push(AppRoutes.chat),
        primaryFabKey: const ValueKey('home-create-note-fab'),
        primaryHeroTag: 'home-create-note-fab',
        primaryIcon: 'assets/icons/feather.svg',
        primaryTooltip: _Strings.newNoteTooltip,
        onPrimaryPressed: () => _openNewNote(context),
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

  Widget _buildNotesBody(List<NoteModel> notes, List<Widget> headerSlivers) {
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

class _NotesLoadingView extends StatelessWidget {
  const _NotesLoadingView({required this.headerSlivers});

  final List<Widget> headerSlivers;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        ...headerSlivers,
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        ),
      ],
    );
  }
}


