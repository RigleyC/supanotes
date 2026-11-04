import 'package:flutter/material.dart';

import 'package:supanotes/features/notes/catalog/model/note_model.dart';
import 'package:supanotes/features/notes/catalog/model/note_strings.dart';
import 'package:supanotes/features/notes/catalog/presentation/widgets/note_icon_interaction_policy.dart';
import 'package:supanotes/features/notes/catalog/presentation/widgets/note_icon_view.dart';
import 'package:supanotes/shared/widgets/app_navigation_bar.dart';
import 'package:supanotes/shared/widgets/confirm_dialog.dart';

/// Typographic list of note titles, anchored to the bottom of the screen.
///
/// A reverse [ListView] pins the rows to the bottom edge when they fit the
/// viewport and scrolls lazily when they overflow. The first (most relevant)
/// note of [notes] is the row nearest the navigation bar. The parent owns
/// the layout and provides scroll constraints.
class NotesListView extends StatelessWidget {
  const NotesListView({
    required this.notes,
    required this.onTap,
    required this.onDelete,
    required this.onToggleFavorite,
    required this.onEditIcon,
    super.key,
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
      padding: EdgeInsets.only(
        top: 8,
        bottom: AppNavigationBar.contentBottomPadding(context),
      ),
      itemCount: notes.length,
      itemBuilder: (context, index) {
        final note = notes[index];
        final canLongPressToEditIcon =
            NoteIconInteractionPolicy.canUseLongPress(
              note: note,
              onEditIcon: () => onEditIcon(note),
            );

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
          child: NoteTitleRow(
            note: note,
            onTap: () => onTap(note),
            onLongPress: canLongPressToEditIcon ? () => onEditIcon(note) : null,
          ),
        );
      },
    );
  }
}

/// One note in the list: its icon, its title in large type, and a star when
/// it is a favorite.
class NoteTitleRow extends StatelessWidget {
  const NoteTitleRow({
    required this.note,
    required this.onTap,
    this.onLongPress,
    super.key,
  });

  final NoteModel note;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final untitled = note.title.trim().isEmpty;
    final title = untitled ? NoteStrings.fallbackTitle : note.title;
    final sharedBy = note.sharedByEmail;
    final favorite = note.favorite ? '. Favorita' : '';
    final semanticsLabel = sharedBy == null
        ? '$title$favorite'
        : '$title$favorite. ${NoteStrings.sharedByPrefix} $sharedBy';

    return Semantics(
      button: true,
      label: semanticsLabel,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onLongPress: onLongPress,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppNavigationBar.contentInset,
              vertical: 10,
            ),
            child: Row(
              children: [
                if (note.noteIcon != null) ...[
                  NoteIconView(icon: note.noteIcon!, size: 22),
                  const SizedBox(width: 12),
                ],
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: (theme.textTheme.titleLarge ?? const TextStyle())
                        .copyWith(
                          fontSize: 20,
                          height: 1.25,
                          fontWeight: FontWeight.w500,
                          letterSpacing: -0.2,
                          color: untitled
                              ? scheme.onSurfaceVariant.withValues(alpha: 0.8)
                              : scheme.onSurface,
                        ),
                  ),
                ),
                if (note.favorite) ...[
                  const SizedBox(width: 6),
                  Icon(
                    Icons.star_rounded,
                    key: ValueKey('note-favorite-${note.id}'),
                    size: 18,
                    color: scheme.tertiary,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
