import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/features/notes/data/notes_repository.dart';
import 'package:supanotes/features/notes/domain/note_model.dart';
import 'package:supanotes/features/notes/presentation/controllers/notes_providers.dart';
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final notesAsync = ref.watch(activeNotesProvider);

    return Container(
      color: scheme.surfaceContainerLow,
      child: Column(
        children: [
          // Header: App Title / Actions
          Container(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.xs,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'SupaNotes',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add, size: 20),
                  tooltip: 'Nova nota',
                  onPressed: widget.onNewNote,
                ),
                if (widget.onOpenSettings != null)
                  IconButton(
                    icon: const Icon(Icons.settings_outlined, size: 20),
                    tooltip: 'Configurações',
                    onPressed: widget.onOpenSettings,
                  ),
              ],
            ),
          ),

          // Search Field
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Buscar notas...',
                hintStyle: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                prefixIcon: const Icon(Icons.search, size: 18),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                filled: true,
                fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (q) => setState(() => _searchQuery = q.trim()),
            ),
          ),

          // Filter tabs: Todas / Favoritas
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            child: Row(
              children: [
                _buildFilterChip(
                  label: 'Todas',
                  isSelected: _activeTab == NoteFilterTab.all,
                  onTap: () => setState(() => _activeTab = NoteFilterTab.all),
                ),
                const SizedBox(width: 6),
                _buildFilterChip(
                  label: 'Favoritas',
                  isSelected: _activeTab == NoteFilterTab.favorites,
                  onTap: () => setState(() => _activeTab = NoteFilterTab.favorites),
                ),
              ],
            ),
          ),

          const Divider(height: 1, thickness: 1),

          // Notes List
          Expanded(
            child: notesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => AppErrorView(
                title: 'Erro ao carregar notas',
                subtitle: e.toString(),
              ),
              data: (notes) {
                var filtered = notes;
                if (_activeTab == NoteFilterTab.favorites) {
                  filtered = filtered.where((n) => n.favorite).toList();
                }
                if (_searchQuery.isNotEmpty) {
                  final q = _searchQuery.toLowerCase();
                  filtered = filtered.where((n) {
                    final titleMatch = n.title.toLowerCase().contains(q);
                    final bodyMatch =
                        (n.excerpt ?? n.content ?? '').toLowerCase().contains(q);
                    return titleMatch || bodyMatch;
                  }).toList();
                }

                if (filtered.isEmpty) {
                  return Center(
                    child: Text(
                      _searchQuery.isNotEmpty
                          ? 'Nenhuma nota encontrada'
                          : 'Nenhuma nota',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final note = filtered[index];
                    final isSelected = note.id == widget.selectedNoteId;
                    return _SidebarNoteTile(
                      note: note,
                      isSelected: isSelected,
                      onTap: () => widget.onNoteTap(note),
                      onToggleFavorite: () {
                        ref
                            .read(notesRepositoryProvider)
                            .toggleFavorite(note.id);
                      },
                      onDelete: () {
                        ref
                            .read(notesRepositoryProvider)
                            .softDelete(note.id);
                        AppMessenger.showSuccess('Nota movida para a lixeira');
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? scheme.primary.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? scheme.primary : scheme.onSurfaceVariant,
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
    required this.note,
    required this.isSelected,
    required this.onTap,
    required this.onToggleFavorite,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: isSelected
            ? scheme.secondaryContainer
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        note.title.isEmpty ? 'Sem título' : note.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.w500,
                          color: isSelected
                              ? scheme.onSecondaryContainer
                              : scheme.onSurface,
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
                              color: isSelected
                                  ? scheme.onSecondaryContainer
                                      .withValues(alpha: 0.7)
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (note.favorite)
                  Icon(
                    Icons.star_rate_rounded,
                    size: 16,
                    color: scheme.tertiary,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
