import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';

import 'package:supanotes/features/notes/catalog/model/note_model.dart';
import 'package:supanotes/shared/widgets/confirm_dialog.dart';
import 'note_icon_view.dart';
import 'note_icon_interaction_policy.dart';

class NoteCard extends StatelessWidget {
  const NoteCard({
    super.key,
    required this.note,
    required this.onTap,
    required this.onDelete,
    required this.onToggleFavorite,
    this.onEditIcon,
  });

  final NoteModel note;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onToggleFavorite;
  final VoidCallback? onEditIcon;

  static const _deleteTitle = 'Apagar nota?';
  static const _deleteMessage = 'Esta acao nao pode ser desfeita.';
  static const _deleteConfirmLabel = 'Apagar';

  static String titleHeroTag(String noteId) => 'note-title-$noteId';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final canLongPressToEditIcon = NoteIconInteractionPolicy.canUseLongPress(
      note: note,
      onEditIcon: onEditIcon,
    );

    return GestureDetector(
      onTap: onTap,
      onLongPress: canLongPressToEditIcon ? onEditIcon : null,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: scheme.shadow.withValues(alpha: 0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Spacer(),
                if (note.favorite)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(
                      Icons.star_rate_rounded,
                      size: 18,
                      color: Theme.of(context).colorScheme.tertiary,
                    ),
                  ),
                AdaptivePopupMenuButton.widget<String>(
                  tint: scheme.onSurfaceVariant,
                  onSelected: (index, entry) {
                    switch (entry.value) {
                      case 'favorite':
                        onToggleFavorite();
                      case 'delete':
                        _confirmDelete(context);
                    }
                  },
                  items: [
                    AdaptivePopupMenuItem<String>(
                      label: note.favorite ? 'Remover favorito' : 'Favoritar',
                      icon: PlatformInfo.isIOS26OrHigher()
                          ? 'star'
                          : (note.favorite ? Icons.star : Icons.star_border),
                      value: 'favorite',
                    ),
                    const AdaptivePopupMenuDivider(),
                    AdaptivePopupMenuItem<String>(
                      label: 'Apagar',
                      icon: PlatformInfo.isIOS26OrHigher()
                          ? 'trash'
                          : Icons.delete_outline,
                      value: 'delete',
                    ),
                  ],
                  child: SizedBox.square(
                    dimension: 38,
                    child: Center(
                      child: Icon(
                        Icons.more_vert_rounded,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (note.noteIcon != null) ...[
                  NoteIconView(icon: note.noteIcon!, size: 22),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Hero(
                    tag: titleHeroTag(note.id),
                    child: Material(
                      type: MaterialType.transparency,
                      child: Text(
                        note.title,
                        style: textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (note.excerpt != null) ...[
              const SizedBox(height: 4),
              Text(
                note.excerpt!,
                style: textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: _deleteTitle,
      message: _deleteMessage,
      confirmLabel: _deleteConfirmLabel,
      destructive: true,
    );
    if (confirmed) onDelete();
  }
}
