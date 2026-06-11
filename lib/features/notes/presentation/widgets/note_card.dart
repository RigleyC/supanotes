import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../shared/widgets/confirm_dialog.dart';
import '../../domain/note_model.dart';

enum _NoteCardAction { favorite, delete }

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
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                PopupMenuButton<_NoteCardAction>(
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.more_vert_rounded),
                  onSelected: (action) {
                    switch (action) {
                      case _NoteCardAction.favorite:
                        onToggleFavorite();
                      case _NoteCardAction.delete:
                        _confirmDelete(context);
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: _NoteCardAction.favorite,
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          note.favorite
                              ? Icons.star
                              : Icons.star_border,
                        ),
                        title: Text(
                          note.favorite
                              ? 'Remover favorito'
                              : 'Favoritar',
                        ),
                      ),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: _NoteCardAction.delete,
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.delete_outline),
                        title: const Text('Apagar'),
                      ),
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
