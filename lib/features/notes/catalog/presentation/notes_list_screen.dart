import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supanotes/shared/widgets/app_button.dart';
import 'package:uuid/uuid.dart';

import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/core/router/app_routes.dart';
import 'package:supanotes/features/settings/presentation/controllers/preferences_controller.dart';
import 'package:supanotes/features/notes/catalog/data/notes_repository.dart';
import 'package:supanotes/features/notes/catalog/model/note_model.dart';
import 'package:supanotes/features/notes/catalog/application/notes_providers.dart';
import 'package:supanotes/features/notes/catalog/presentation/widgets/notes_grid_view.dart';
import 'package:supanotes/features/notes/catalog/presentation/widgets/notes_list_view.dart';
import 'package:supanotes/features/notes/catalog/presentation/widgets/note_icon_picker.dart';

import 'package:supanotes/shared/widgets/app_error_view.dart';
import 'package:supanotes/shared/widgets/app_snackbar.dart';

import 'package:supanotes/features/notes/catalog/presentation/widgets/notes_more_menu.dart';

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

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0),
                Theme.of(context).scaffoldBackgroundColor,
              ],
            ),
          ),
        ),
        actions: [
          if (_isSearching)
            ConstrainedBox(
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
            )
          else
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: _openSearch,
            ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: _closeSearch,
          ),
          NotesMoreMenu(
            isListView: !isGridView,
            onToggleViewMode: _toggleViewMode,
            onLogout: () => ref.read(authControllerProvider.notifier).logout(),
            onOpenSettings: () => context.push(AppRoutes.settings),
          ),
        ],
      ),
      body: SafeArea(
        top: true,
        child: notesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AppErrorView(
          title: 'Erro ao carregar as notas',
          subtitle: e.toString(),
        ),
        data: (notes) {
          final filteredNotes = trimmedSearchQuery.isEmpty
              ? notes
              : notes.where((n) {
                  final q = trimmedSearchQuery.toLowerCase();
                  final bodyText = (n.excerpt ?? n.content).toLowerCase();
                  return n.title.toLowerCase().contains(q) ||
                      bodyText.contains(q);
                }).toList();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: isGridView
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
                      ),
              ),
            ],
          );
        },
      ),
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
    } catch (_) {
      if (!context.mounted) return;
      AppMessenger.showError('Erro ao salvar preferência de visualização');
    }
  }
}
