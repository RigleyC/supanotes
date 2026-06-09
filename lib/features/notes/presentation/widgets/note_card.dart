import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../shared/theme/app_spacing.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../domain/note_model.dart';

class NoteCard extends StatelessWidget {
  const NoteCard({
    super.key,
    required this.note,
    required this.onTap,
  });

  final NoteModel note;
  final VoidCallback onTap;

  static const _fallbackTitle = 'Sem título';

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
              if (note.favorite)
                Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.sm),
                  child: Icon(
                    Icons.star,
                    size: 18,
                    color: scheme.tertiary,
                  ),
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
    );
  }
}
