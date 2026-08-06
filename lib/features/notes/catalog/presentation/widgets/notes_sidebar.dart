import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/features/auth/domain/user.dart';
import 'package:supanotes/features/notes/catalog/application/notes_providers.dart';
import 'package:supanotes/features/notes/catalog/data/notes_repository.dart';
import 'package:supanotes/features/notes/catalog/model/note_model.dart';
import 'package:supanotes/features/notes/catalog/presentation/widgets/note_context_menu.dart';
import 'package:supanotes/shared/theme/desktop_layout_tokens.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/widgets/app_error_view.dart';
import 'package:supanotes/shared/widgets/app_icon_button.dart';
import 'package:supanotes/shared/widgets/app_snackbar.dart';

class NotesSidebar extends ConsumerStatefulWidget {
  final String? selectedNoteId;
  final ValueChanged<NoteModel> onNoteTap;
  final VoidCallback onNewNote;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onToggleCollapsed;

  const NotesSidebar({
    super.key,
    required this.selectedNoteId,
    required this.onNoteTap,
    required this.onNewNote,
    this.onOpenSettings,
    this.onToggleCollapsed,
  });

  @override
  ConsumerState<NotesSidebar> createState() => _NotesSidebarState();
}

class _NotesSidebarState extends ConsumerState<NotesSidebar> {
  String _searchQuery = '';

  List<NoteModel> _searchNotes(List<NoteModel> notes) {
    if (_searchQuery.isEmpty) return notes;

    final query = _searchQuery.toLowerCase();
    return notes.where((note) {
      final titleMatch = note.title.toLowerCase().contains(query);
      final bodyMatch = (note.excerpt ?? note.content ?? '')
          .toLowerCase()
          .contains(query);
      return titleMatch || bodyMatch;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final notesAsync = ref.watch(activeNotesProvider);
    final accountAsync = ref.watch(authControllerProvider);

    return Column(
      children: [
        _SidebarHeader(
          onNewNote: widget.onNewNote,
          onToggleCollapsed: widget.onToggleCollapsed,
        ),
        _SidebarSearchField(
          onChanged: (query) => setState(() => _searchQuery = query.trim()),
        ),
        Divider(
          height: DesktopLayoutTokens.dividerWidth,
          thickness: DesktopLayoutTokens.dividerWidth,
        ),
        const SizedBox(
          key: ValueKey('desktop-sidebar-note-list-gap'),
          height: AppSpacing.sm,
        ),
        Expanded(
          child: notesAsync.when(
            loading: () =>
                const Center(child: CircularProgressIndicator(strokeWidth: 2)),
            error: (error, _) => AppErrorView(
              title: 'Erro ao carregar notas',
              subtitle: error.toString(),
            ),
            data: (notes) => _SidebarNotesList(
              notes: _searchNotes(notes),
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
          _SidebarFooter(
            accountAsync: accountAsync,
            onOpenSettings: widget.onOpenSettings!,
          ),
      ],
    );
  }
}

class _SidebarHeader extends StatelessWidget {
  const _SidebarHeader({
    required this.onNewNote,
    required this.onToggleCollapsed,
  });

  final VoidCallback onNewNote;
  final VoidCallback? onToggleCollapsed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: DesktopLayoutTokens.chromeHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: DesktopLayoutTokens.sidebarContentPadding,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (onToggleCollapsed != null)
              AppIconButton(
                key: const ValueKey('desktop-sidebar-collapse'),
                icon: const Icon(Icons.chevron_left),
                tooltip: 'Recolher sidebar',
                onPressed: onToggleCollapsed,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 44,
                  height: 44,
                ),
              ),
            if (onToggleCollapsed != null) const SizedBox(width: AppSpacing.xs),
            AppIconButton(
              key: const ValueKey('desktop-sidebar-new-note'),
              icon: const Icon(Icons.add, size: 20),
              tooltip: 'Nova nota',
              onPressed: onNewNote,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 44, height: 44),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
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
        DesktopLayoutTokens.sidebarContentPadding,
        AppSpacing.xs,
        DesktopLayoutTokens.sidebarContentPadding,
        AppSpacing.xs,
      ),
      child: SizedBox(
        height: DesktopLayoutTokens.chromeControlHeight,
        child: TextField(
          onChanged: onChanged,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Buscar notas...',
            hintStyle: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            prefixIcon: const Icon(Icons.search, size: 18),
            prefixIconConstraints: const BoxConstraints(
              minWidth: DesktopLayoutTokens.chromeControlHeight,
              minHeight: DesktopLayoutTokens.chromeControlHeight,
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
  const _SidebarFooter({
    required this.accountAsync,
    required this.onOpenSettings,
  });

  final AsyncValue<User?> accountAsync;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accountLabel = accountAsync.when(
      data: (account) => account?.email ?? 'Conta desconectada',
      loading: () => 'Carregando conta…',
      error: (_, _) => 'Conta indisponível',
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DesktopLayoutTokens.sidebarContentPadding,
        AppSpacing.xs,
        DesktopLayoutTokens.sidebarContentPadding,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            label: 'Configurações',
            child: ConstrainedBox(
              key: const ValueKey('desktop-sidebar-settings-action'),
              constraints: const BoxConstraints(minHeight: 44),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(
                  DesktopLayoutTokens.chromeRadius,
                ),
                child: InkWell(
                  onTap: onOpenSettings,
                  borderRadius: BorderRadius.circular(
                    DesktopLayoutTokens.chromeRadius,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.settings_outlined,
                          size: 18,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            'Configurações',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                Icon(
                  Icons.account_circle_outlined,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    accountLabel,
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
        ],
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

    final tile = NoteContextMenuWidget(
      note: note,
      onToggleFavorite: onToggleFavorite,
      onDelete: onDelete,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
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
    return tile;
  }
}
