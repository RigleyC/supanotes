import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/core/router/app_routes.dart';
import 'package:supanotes/features/notes/catalog/application/notes_providers.dart';
import 'package:supanotes/features/notes/catalog/data/notes_repository.dart';
import 'package:supanotes/features/notes/catalog/model/note_model.dart';
import 'package:supanotes/features/notes/catalog/presentation/widgets/note_icon_picker.dart';
import 'package:supanotes/features/notes/catalog/presentation/widgets/notes_grid_view.dart';
import 'package:supanotes/features/notes/catalog/presentation/widgets/notes_list_view.dart';
import 'package:supanotes/features/notes/catalog/presentation/widgets/notes_more_menu.dart';
import 'package:supanotes/features/settings/presentation/controllers/preferences_controller.dart';
import 'package:supanotes/shared/widgets/app_error_view.dart';
import 'package:supanotes/shared/widgets/app_navigation_bar.dart';
import 'package:supanotes/shared/widgets/app_snackbar.dart';
import 'package:uuid/uuid.dart';

/// Creates an empty local note and opens it in the editor.
///
/// Shared by the notes list and the navigation shell's "+" action, so it only
/// needs a [BuildContext] below the [ProviderScope] and the router.
Future<void> createAndOpenNote(BuildContext context) async {
  final id = const Uuid().v4();
  await ProviderScope.containerOf(
    context,
    listen: false,
  ).read(notesRepositoryProvider).createLocalNote(id: id);
  if (!context.mounted) return;
  unawaited(context.push(AppRoutes.note(id)));
}

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
    final normalizedSearchQuery = _searchQuery.trim().toLowerCase();
    // Full-content matches come from the database; until they load, fall back
    // to the title/excerpt already in memory so typing stays responsive.
    final contentMatches = normalizedSearchQuery.isEmpty
        ? null
        : ref.watch(noteSearchMatchesProvider(normalizedSearchQuery)).value;

    return Scaffold(
      appBar: _buildAppBar(context, isGridView: isGridView),
      body: notesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AppErrorView(
          title: 'Erro ao carregar as notas',
          subtitle: e.toString(),
        ),
        data: (notes) => _buildNotes(
          _filterNotes(notes, normalizedSearchQuery, contentMatches),
          normalizedSearchQuery: normalizedSearchQuery,
          isGridView: isGridView,
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context, {
    required bool isGridView,
  }) {
    return AppBar(
      automaticallyImplyLeading: false,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      actions: [
        if (_isSearching)
          _buildSearchField(context)
        else
          IconButton(
            tooltip: 'Buscar notas',
            icon: const Icon(Icons.search),
            onPressed: _openSearch,
          ),
        if (_isSearching)
          IconButton(icon: const Icon(Icons.close), onPressed: _closeSearch),
        NotesMoreMenu(
          isListView: !isGridView,
          onToggleViewMode: _toggleViewMode,
          onLogout: () => ref.read(authControllerProvider.notifier).logout(),
          onOpenSettings: () => context.push(AppRoutes.settings),
        ),
        const SizedBox(width: 12),
      ],
    );
  }

  Widget _buildSearchField(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: TextField(
        key: const ValueKey('notes-inline-search-field'),
        autofocus: true,
        decoration: InputDecoration(
          hintText: 'Buscar notas',
          prefixIcon: const Icon(Icons.search),
          border: InputBorder.none,
          filled: true,
          fillColor: Theme.of(context).colorScheme.surface,
        ),
        onChanged: _onSearchQueryChanged,
      ),
    );
  }

  /// Notes matching [normalizedSearchQuery] by full content (when the database
  /// matches are loaded) or by in-memory title/excerpt.
  static List<NoteModel> _filterNotes(
    List<NoteModel> notes,
    String normalizedSearchQuery,
    Set<String>? contentMatches,
  ) {
    if (normalizedSearchQuery.isEmpty) return notes;
    return notes.where((n) {
      if (contentMatches?.contains(n.id) ?? false) {
        return true;
      }
      final bodyText = (n.excerpt ?? n.content).toLowerCase();
      return n.title.toLowerCase().contains(normalizedSearchQuery) ||
          bodyText.contains(normalizedSearchQuery);
    }).toList();
  }

  Widget _buildNotes(
    List<NoteModel> filteredNotes, {
    required String normalizedSearchQuery,
    required bool isGridView,
  }) {
    if (filteredNotes.isEmpty) {
      return _buildEmptyState(normalizedSearchQuery);
    }

    return isGridView
        ? NotesGridView(
            key: const ValueKey('grid'),
            notes: filteredNotes,
            onTap: _openNote,
            onDelete: _deleteNote,
            onToggleFavorite: _toggleFavorite,
            onEditIcon: _editNoteIcon,
          )
        : NotesListView(
            key: const ValueKey('list'),
            notes: filteredNotes,
            onTap: _openNote,
            onDelete: _deleteNote,
            onToggleFavorite: _toggleFavorite,
            onEditIcon: _editNoteIcon,
          );
  }

  static Widget _buildEmptyState(String normalizedSearchQuery) {
    final isSearching = normalizedSearchQuery.isNotEmpty;
    return _NotesEmptyMessage(
      key: const ValueKey('notes-empty-state'),
      title: isSearching ? 'Nenhuma nota encontrada' : 'Nenhuma nota ainda',
      subtitle: isSearching
          ? 'Tente buscar por outro termo.'
          : 'Crie uma nota para começar.',
    );
  }

  void _openNote(NoteModel note) => context.push(AppRoutes.note(note.id));

  Future<void> _deleteNote(NoteModel note) async {
    try {
      await ref.read(notesRepositoryProvider).softDelete(note.id);
    } on Object catch (error, stackTrace) {
      debugPrint('Failed to delete note ${note.id}: $error\n$stackTrace');
      if (mounted) AppMessenger.showError('Não foi possível apagar a nota');
      return;
    }
    if (!mounted) return;
    AppMessenger.showSuccess('Nota movida para a lixeira');
  }

  void _toggleFavorite(NoteModel note) {
    unawaited(ref.read(notesRepositoryProvider).toggleFavorite(note.id));
  }

  Future<void> _editNoteIcon(NoteModel note) async {
    await showNoteIconPicker(
      context: context,
      note: note,
      onSelected: (icon) =>
          ref.read(notesRepositoryProvider).updateNoteIcon(note.id, icon),
    );
  }

  Future<void> _toggleViewMode() async {
    try {
      await ref
          .read(preferencesControllerProvider.notifier)
          .toggleNotesViewMode();
    } on Object catch (_) {
      if (!context.mounted) return;
      AppMessenger.showError('Erro ao salvar preferência de visualização');
    }
  }
}

/// Quiet, bottom-anchored message shown when there is no note to list.
class _NotesEmptyMessage extends StatelessWidget {
  const _NotesEmptyMessage({
    required this.title,
    required this.subtitle,
    super.key,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyLarge?.copyWith(
      fontSize: 17,
      height: 1.4,
      letterSpacing: -0.1,
      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
    );
    return Align(
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppNavigationBar.contentInset,
          0,
          AppNavigationBar.contentInset,
          AppNavigationBar.contentBottomPadding(context),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: style?.copyWith(fontWeight: FontWeight.w500)),
            Text(subtitle, style: style),
          ],
        ),
      ),
    );
  }
}
