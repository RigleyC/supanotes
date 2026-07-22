import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supanotes/shared/widgets/app_button.dart';
import 'package:uuid/uuid.dart';

import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/core/router/app_routes.dart';
import 'package:supanotes/features/settings/presentation/controllers/preferences_controller.dart';
import 'package:supanotes/features/notes/data/notes_repository.dart';
import 'package:supanotes/features/notes/domain/note_model.dart';
import 'package:supanotes/features/notes/presentation/controllers/notes_providers.dart';
import 'package:supanotes/features/notes/presentation/widgets/notes_grid_view.dart';
import 'package:supanotes/features/notes/presentation/widgets/notes_list_view.dart';

import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/widgets/app_error_view.dart';
import 'package:supanotes/shared/widgets/app_snackbar.dart';

import 'package:supanotes/features/notes/presentation/widgets/notes_more_menu.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

class NotesListScreen extends ConsumerStatefulWidget {
  const NotesListScreen({super.key});

  @override
  ConsumerState<NotesListScreen> createState() => _NotesListScreenState();
}

class _NotesListScreenState extends ConsumerState<NotesListScreen> {
  bool _isSearching = false;
  String _searchQuery = '';
  Timer? _searchDebounce;

  void _openSearch() {
    setState(() => _isSearching = true);
  }

  void _closeSearch() {
    _searchDebounce?.cancel();
    setState(() {
      _isSearching = false;
      _searchQuery = '';
    });
  }

  void _onSearchQueryChanged(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _searchQuery = query.trim());
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isGridView = ref.watch(isGridViewProvider);
    final notesAsync = ref.watch(activeNotesProvider);
    final trimmedSearchQuery = _searchQuery.trim();

    final headerSlivers = [
      SliverToBoxAdapter(
        child: SizedBox(
          height:
              kToolbarHeight +
              AppSpacing.lg +
              (PlatformInfo.isIOS26OrHigher()
                  ? AppSpacing.ios26ToolbarHeight
                  : 8),
        ),
      ),
      if (_isSearching)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              0,
              AppSpacing.md,
              AppSpacing.md,
            ),
            child: TextField(
              key: const ValueKey('notes-inline-search-field'),
              decoration: const InputDecoration(
                hintText: 'Buscar notas',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: _onSearchQueryChanged,
            ),
          ),
        ),
    ];

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
            child: Container(color: Colors.transparent),
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: _isSearching ? _closeSearch : _openSearch,
          ),
          NotesMoreMenu(
            isListView: !isGridView,
            onToggleViewMode: _toggleViewMode,
            onLogout: () => ref.read(authControllerProvider.notifier).logout(),
            onOpenSettings: () => context.push(AppRoutes.settings),
          ),
        ],
      ),
      body: notesAsync.when(
        loading: () => CustomScrollView(
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            ),
          ],
        ),
        error: (e, _) => AppErrorView(
          title: 'Erro ao carregar as notas',
          subtitle: e.toString(),
        ),
        data: (notes) {
          final filteredNotes = trimmedSearchQuery.isEmpty
              ? notes
              : notes.where((n) {
                  final q = trimmedSearchQuery.toLowerCase();
                  final bodyText = (n.excerpt ?? n.content ?? '').toLowerCase();
                  return n.title.toLowerCase().contains(q) ||
                      bodyText.contains(q);
                }).toList();
          return CustomScrollView(
            slivers: [
              ...headerSlivers,
              _buildNotesBody(filteredNotes, isGridView),
            ],
          );
        },
      ),

      floatingActionButton: AppButton(
        variant: AppButtonVariant.fab,
        onPressed: () => _openNewNote(context),
        icon: const Icon(Icons.add),
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
    AppMessenger.showSuccess('Nota movida para a lixeira');
  }

  void _toggleFavorite(NoteModel note) {
    ref.read(notesRepositoryProvider).toggleFavorite(note.id);
  }

  Future<void> _toggleViewMode() async {
    try {
      await ref
          .read(preferencesControllerProvider.notifier)
          .toggleNotesViewMode();
    } catch (_) {
      if (!context.mounted) return;
      AppMessenger.showError('Erro ao salvar preferência de visualização');
    }
  }

  Widget _buildNotesBody(List<NoteModel> notes, bool isGridView) {
    return isGridView
        ? NotesGridView(
            key: const ValueKey('grid'),
            notes: notes.toList(),
            onTap: _openNote,
            onDelete: _deleteNote,
            onToggleFavorite: _toggleFavorite,
          )
        : NotesListView(
            key: const ValueKey('list'),
            notes: notes.toList(),
            onTap: _openNote,
            onDelete: _deleteNote,
            onToggleFavorite: _toggleFavorite,
          );
  }
}
