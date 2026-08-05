import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/features/notes/catalog/application/notes_providers.dart';
import 'package:supanotes/features/notes/catalog/data/notes_repository.dart';
import 'package:supanotes/features/notes/catalog/model/note_model.dart';
import 'package:supanotes/features/notes/catalog/presentation/widgets/note_context_menu.dart';
import 'package:supanotes/shared/theme/desktop_layout_tokens.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/widgets/app_error_view.dart';
import 'package:supanotes/shared/widgets/app_snackbar.dart';

enum NoteFilterTab { all, favorites }

class NotesSidebar extends ConsumerStatefulWidget {
  final String? selectedNoteId;
  final ValueChanged<NoteModel> onNoteTap;
  final VoidCallback onNewNote;
  final VoidCallback? onOpenSettings;

  const NotesSidebar({
    super.key,
    required this.selectedNoteId,
    required this.onNoteTap,
    required this.onNewNote,
    this.onOpenSettings,
  });

  @override
  ConsumerState<NotesSidebar> createState() => _NotesSidebarState();
}

class _NotesSidebarState extends ConsumerState<NotesSidebar> {
  String _searchQuery = '';
  NoteFilterTab _activeTab = NoteFilterTab.all;

  List<NoteModel> _filterNotes(List<NoteModel> notes) {
    var result = notes;
    if (_activeTab == NoteFilterTab.favorites) {
      result = result.where((note) => note.favorite).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      result = result.where((note) {
        final titleMatch = note.title.toLowerCase().contains(query);
        final bodyMatch = (note.excerpt ?? note.content ?? '')
            .toLowerCase()
            .contains(query);
        return titleMatch || bodyMatch;
      }).toList();
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final notesAsync = ref.watch(activeNotesProvider);

    return ColoredBox(
      color: scheme.surfaceContainerLow,
      child: Column(
        children: [
          _SidebarHeader(onNewNote: widget.onNewNote),
          _SidebarSearchField(
            onChanged: (query) => setState(() => _searchQuery = query.trim()),
          ),
          _SidebarFilterBar(
            activeTab: _activeTab,
            onTabSelected: (tab) => setState(() => _activeTab = tab),
          ),
          Divider(
            height: DesktopLayoutTokens.dividerWidth,
            thickness: DesktopLayoutTokens.dividerWidth,
          ),
          Expanded(
            child: notesAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              error: (error, _) => AppErrorView(
                title: 'Erro ao carregar notas',
                subtitle: error.toString(),
              ),
              data: (notes) => _SidebarNotesList(
                notes: _filterNotes(notes),
                searchQuery: _searchQuery,
                selectedNoteId: widget.selectedNoteId,
                onNoteTap: widget.onNoteTap,
                onToggleFavorite: (note) {
                  ref.read(notesRepositoryProvider).toggleFavorite(note.id);
                },
                onDelete: (note) {
                  ref.read(notesRepositoryProvider).softDelete(note.id);
                  AppMessenger.showSuccess('Nota movida para a lixeira');
                },
              ),
            ),
          ),
          if (widget.onOpenSettings != null)
            _SidebarFooter(onOpenSettings: widget.onOpenSettings!),
        ],
      ),
    );
  }
}

class _SidebarHeader extends StatelessWidget {
  const _SidebarHeader({required this.onNewNote});

  final VoidCallback onNewNote;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.xs,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'SupaNotes',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add, size: 20),
            tooltip: 'Nova nota',
            onPressed: onNewNote,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 44, height: 44),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _SidebarSearchField extends StatelessWidget {
  const _SidebarSearchField({required this.onChanged});

  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      child: SizedBox(
        height: 36,
        child: TextField(
          onChanged: onChanged,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Buscar notas...',
            hintStyle: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            prefixIcon: const Icon(Icons.search, size: 18),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 36,
              minHeight: 36,
            ),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10),
            filled: true,
            fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(
                DesktopLayoutTokens.chromeRadius,
              ),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(
                DesktopLayoutTokens.chromeRadius,
              ),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(
                DesktopLayoutTokens.chromeRadius,
              ),
              borderSide: BorderSide(color: scheme.primary, width: 1),
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarFilterBar extends StatelessWidget {
  const _SidebarFilterBar({
    required this.activeTab,
    required this.onTabSelected,
  });

  final NoteFilterTab activeTab;
  final ValueChanged<NoteFilterTab> onTabSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      child: Row(
        children: [
          _SidebarFilterButton(
            label: 'Todas',
            selected: activeTab == NoteFilterTab.all,
            onTap: () => onTabSelected(NoteFilterTab.all),
          ),
          const SizedBox(width: AppSpacing.xs),
          _SidebarFilterButton(
            label: 'Favoritas',
            selected: activeTab == NoteFilterTab.favorites,
            onTap: () => onTabSelected(NoteFilterTab.favorites),
          ),
        ],
      ),
    );
  }
}

class _SidebarFilterButton extends StatelessWidget {
  const _SidebarFilterButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = selected ? scheme.primary : scheme.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: selected
            ? scheme.primary.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(DesktopLayoutTokens.chromeRadius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(DesktopLayoutTokens.chromeRadius),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: foreground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarNotesList extends StatelessWidget {
  const _SidebarNotesList({
    required this.notes,
    required this.searchQuery,
    required this.selectedNoteId,
    required this.onNoteTap,
    required this.onToggleFavorite,
    required this.onDelete,
  });

  final List<NoteModel> notes;
  final String searchQuery;
  final String? selectedNoteId;
  final ValueChanged<NoteModel> onNoteTap;
  final ValueChanged<NoteModel> onToggleFavorite;
  final ValueChanged<NoteModel> onDelete;

  @override
  Widget build(BuildContext context) {
    if (notes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Text(
            searchQuery.isNotEmpty ? 'Nenhuma nota encontrada' : 'Nenhuma nota',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      itemCount: notes.length,
      itemBuilder: (context, index) {
        final note = notes[index];
        return _SidebarNoteTile(
          key: ValueKey(note.id),
          note: note,
          isSelected: note.id == selectedNoteId,
          onTap: () => onNoteTap(note),
          onToggleFavorite: () => onToggleFavorite(note),
          onDelete: () => onDelete(note),
        );
      },
    );
  }
}

class _SidebarFooter extends StatelessWidget {
  const _SidebarFooter({required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.xs,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(DesktopLayoutTokens.chromeRadius),
        child: InkWell(
          onTap: onOpenSettings,
          borderRadius: BorderRadius.circular(DesktopLayoutTokens.chromeRadius),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                Icon(
                  Icons.settings_outlined,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'Configurações',
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarNoteTile extends StatelessWidget {
  final NoteModel note;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;
  final VoidCallback onDelete;

  const _SidebarNoteTile({
    super.key,
    required this.note,
    required this.isSelected,
    required this.onTap,
    required this.onToggleFavorite,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return NoteContextMenuWidget(
      note: note,
      onToggleFavorite: onToggleFavorite,
      onDelete: onDelete,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 1,
        ),
        child: Material(
          color: isSelected
              ? scheme.surfaceContainerHighest.withValues(alpha: 0.8)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(DesktopLayoutTokens.chromeRadius),
          child: InkWell(
            borderRadius: BorderRadius.circular(
              DesktopLayoutTokens.chromeRadius,
            ),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: DesktopLayoutTokens.sidebarRowHeight,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            note.title.isEmpty ? 'Sem título' : note.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color: scheme.onSurface,
                            ),
                          ),
                          if (note.excerpt != null && note.excerpt!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                note.excerpt!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (note.favorite)
                      Padding(
                        padding: const EdgeInsets.only(left: AppSpacing.xs),
                        child: Icon(
                          Icons.star_rate_rounded,
                          size: 16,
                          color: scheme.tertiary,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
