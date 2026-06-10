import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../shared/theme/app_spacing.dart';
import '../../../../shared/widgets/app_card.dart';
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

  String? _resolveExcerpt(NoteModel note) {
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
    final excerpt = _resolveExcerpt(note);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withOpacity(0.1),
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
              //Abre um popupmenu com as ações de favoritar e deletar
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                splashColor: Colors.transparent,
                onPressed: () {},
                icon: Icon(Icons.more_vert_rounded),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            title,
            style: textTheme.titleMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            note.content,
            style: textTheme.bodyMedium,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
    /* 
    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Hero(
                  tag: titleHeroTag(note.id),
                  child: Material(
                    type: MaterialType.transparency,
                    child: Text(
                      title,
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 32,
                  height: 32,
                ),
                icon: Icon(
                  note.favorite ? Icons.star : Icons.star_border,
                  size: 18,
                  color: note.favorite
                      ? scheme.tertiary
                      : scheme.onSurfaceVariant,
                ),
                onPressed: onToggleFavorite,
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 32,
                  height: 32,
                ),
                icon: Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
                onPressed: () => _confirmDelete(context),
              ),
            ],
          ),
          if (excerpt != null && excerpt.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
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
    ); */
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
