import 'package:flutter/material.dart';

import 'package:supanotes/features/notes/catalog/model/note_model.dart';
import 'package:supanotes/features/notes/catalog/model/note_strings.dart';
import 'package:supanotes/features/notes/catalog/presentation/widgets/note_icon_interaction_policy.dart';
import 'package:supanotes/features/notes/catalog/presentation/widgets/note_icon_view.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/widgets/app_tile.dart';
import 'package:supanotes/shared/widgets/confirm_dialog.dart';

/// List representation of the notes list, anchored to the bottom.
///
/// A reverse [ListView] pins the rows to the bottom edge when they fit the
/// viewport and scrolls lazily when they overflow. Because a reversed list
/// renders the first item at the bottom, the input order is inverted so the
/// visual order stays top-to-bottom. The parent owns the layout (e.g. a
/// [Column]) and provides scroll constraints via [Expanded].
class NotesListView extends StatelessWidget {
  const NotesListView({
    required this.notes, required this.onTap, required this.onDelete, required this.onToggleFavorite, required this.onEditIcon, super.key,
  });

  final List<NoteModel> notes;
  final void Function(NoteModel note) onTap;
  final void Function(NoteModel note) onDelete;
  final void Function(NoteModel note) onToggleFavorite;
  final void Function(NoteModel note) onEditIcon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
        0,
      ),
      itemCount: notes.length,
      itemBuilder: (context, index) {
        final note = notes[notes.length - 1 - index];
        final canLongPressToEditIcon =
            NoteIconInteractionPolicy.canUseLongPress(
          note: note,
          onEditIcon: () => onEditIcon(note),
        );

        final Widget? leading = note.noteIcon != null
            ? NoteIconView(icon: note.noteIcon!)
            : null;

        final Widget? subtitleWidget = note.sharedByEmail != null
            ? Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.person_outline,
                      size: 14,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        '${NoteStrings.sharedFromPrefix} ${note.sharedByEmail}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              )
            : null;

        final Widget? trailing = note.favorite
            ? Icon(
                Icons.star_rate_rounded,
                size: 18,
                color: scheme.tertiary,
              )
            : null;

        return Dismissible(
          key: ValueKey('note-${note.id}'),
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
              onToggleFavorite(note);
              return false;
            }
            final confirmed = await showConfirmDialog(
              context: context,
              title: NoteStrings.deleteConfirmTitle,
              message: NoteStrings.deleteConfirmMessage,
              confirmLabel: NoteStrings.deleteConfirmLabel,
              destructive: true,
            );
            if (confirmed) onDelete(note);
            return confirmed;
          },
          child: AppTile(
            title: note.title,
            leading: leading,
            trailing: trailing,
            subtitleWidget: subtitleWidget,
            onTap: () => onTap(note),
            onLongPress: canLongPressToEditIcon ? () => onEditIcon(note) : null,
          ),
        );
      },
    );
  }
}
