import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../shared/widgets/confirm_dialog.dart';
import '../../domain/note_model.dart';

class NoteCard extends StatelessWidget {
  const NoteCard({
    super.key,
    required this.note,
    required this.onTap,
    required this.onDelete,
    required this.onToggleFavorite,
  });

  final NoteModel note;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onToggleFavorite;

  static const _fallbackTitle = 'Sem titulo';
  static const _deleteTitle = 'Apagar nota?';
  static const _deleteMessage = 'Esta acao nao pode ser desfeita.';
  static const _deleteConfirmLabel = 'Apagar';

  static String titleHeroTag(String noteId) => 'note-title-$noteId';

  String? _resolveExcerpt() {
    if (note.excerpt != null && note.excerpt!.trim().isNotEmpty) {
      return note.excerpt!.trim();
    }
    if (note.content.isEmpty) return null;
    final flat = note.content.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (flat.length <= AppConstants.noteExcerptMaxLength) return flat;
    return '${flat.substring(0, AppConstants.noteExcerptMaxLength)}…';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final title = note.title?.trim().isNotEmpty == true
        ? note.title!.trim()
        : _fallbackTitle;
    final excerpt = _resolveExcerpt();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.surface,
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
                AdaptivePopupMenuButton.icon<String>(
                  icon: PlatformInfo.isIOS26OrHigher()
                      ? 'ellipsis.vertical'
                      : Icons.more_vert_rounded,
                  onSelected: (index, entry) {
                    switch (entry.value) {
                      case 'favorite':
                        onToggleFavorite();
                      case 'delete':
                        _confirmDelete(context);
                    }
                  },
                  size: 38,
                  items: [
                    AdaptivePopupMenuItem<String>(
                      label: note.favorite
                          ? 'Remover favorito'
                          : 'Favoritar',
                      icon: PlatformInfo.isIOS26OrHigher()
                          ? 'star'
                          : (note.favorite
                              ? Icons.star
                              : Icons.star_border),
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
                ),
              ],
            ),
            const SizedBox(height: 8),
            Hero(
              tag: titleHeroTag(note.id),
              child: Material(
                type: MaterialType.transparency,
                child: Text(
                  title,
                  style: textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            if (excerpt != null && excerpt.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                excerpt,
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
