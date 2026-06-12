import 'package:flutter/material.dart';

import '../../../../shared/widgets/confirm_dialog.dart';
import '../../domain/note_model.dart';

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

  static const _fallbackTitle = 'Sem título';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = note.title?.trim().isNotEmpty == true
        ? note.title!.trim()
        : _fallbackTitle;

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
        if (direction != DismissDirection.endToStart) return true;
        final confirmed = await showConfirmDialog(
          context: context,
          title: 'Apagar nota?',
          message: 'Esta ação não pode ser desfeita.',
          confirmLabel: 'Apagar',
          destructive: true,
        );
        if (confirmed) onDelete();
        return confirmed;
      },
      onDismissed: (direction) {
        if (direction == DismissDirection.startToEnd) onToggleFavorite();
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
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
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
