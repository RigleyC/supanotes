import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import 'package:supanotes/features/notes/catalog/model/note_model.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'note_card.dart';

/// Grid representation of the notes list.
///
/// Returns a [MasonryGridView] — no slivers of its own. The parent owns the
/// layout (e.g. a [Column]) and provides scroll constraints via [Expanded].
class NotesGridView extends StatelessWidget {
  const NotesGridView({
    super.key,
    required this.notes,
    required this.onTap,
    required this.onDelete,
    required this.onToggleFavorite,
    required this.onEditIcon,
  });

  final List<NoteModel> notes;
  final void Function(NoteModel note) onTap;
  final void Function(NoteModel note) onDelete;
  final void Function(NoteModel note) onToggleFavorite;
  final void Function(NoteModel note) onEditIcon;

  @override
  Widget build(BuildContext context) {
    return MasonryGridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: AppSpacing.sm,
      crossAxisSpacing: AppSpacing.sm,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
        80 + AppSpacing.sm,
      ),
      itemCount: notes.length,
      itemBuilder: (context, index) {
        final note = notes[index];
        return NoteCard(
          key: ValueKey(note.id),
          note: note,
          onTap: () => onTap(note),
          onDelete: () => onDelete(note),
          onToggleFavorite: () => onToggleFavorite(note),
          onEditIcon: () => onEditIcon(note),
        );
      },
    );
  }
}