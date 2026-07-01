import 'package:flutter/material.dart';

import '../../../../shared/widgets/confirm_dialog.dart';
import '../../domain/note_model.dart';
import '../../domain/note_strings.dart';

class NoteListRow extends StatelessWidget {
  const NoteListRow({
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = note.title;

    return Dismissible(
      key: ValueKey('note-${note.id}'),
      direction: DismissDirection.horizontal,
      background: Container(
        color: scheme.primaryContainer,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Icon(
          note.favorite ? Icons.star_border_rounded : Icons.star_border,
          color: scheme.onPrimaryContainer,
        ),
      ),
      secondaryBackground: Container(
        color: scheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          onToggleFavorite();
          return false;
        }
        final confirmed = await showConfirmDialog(
          context: context,
          title: NoteStrings.deleteConfirmTitle,
          message: NoteStrings.deleteConfirmMessage,
          confirmLabel: NoteStrings.deleteConfirmLabel,
          destructive: true,
        );
        if (confirmed) onDelete();
        return confirmed;
      },
      child: InkWell(
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (note.sharedByEmail != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(
                          children: [
                            Icon(
                              Icons.person_outline,
                              size: 14,
                              color: scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${NoteStrings.sharedFromPrefix} ${note.sharedByEmail}',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              if (note.favorite)
                Icon(Icons.star_rate_rounded, size: 18, color: scheme.tertiary),
            ],
          ),
        ),
      ),
    );
  }
}
