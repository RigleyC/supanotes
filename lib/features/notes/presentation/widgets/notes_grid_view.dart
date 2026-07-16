import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../../../../shared/theme/app_spacing.dart';
import '../../domain/note_model.dart';
import 'note_card.dart';

/// Grid representation of the notes list.
///
/// Returns a [SliverPadding] wrapping a [SliverMasonryGrid] — no
/// [CustomScrollView] of its own. The parent owns the scroll view and
/// any leading slivers.
class NotesGridView extends StatelessWidget {
  const NotesGridView({
    super.key,
    required this.notes,
    required this.onTap,
    required this.onDelete,
    required this.onToggleFavorite,
  });

  final List<NoteModel> notes;
  final void Function(NoteModel note) onTap;
  final void Function(NoteModel note) onDelete;
  final void Function(NoteModel note) onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
        80 + AppSpacing.sm,
      ),
      sliver: SliverMasonryGrid.count(
        crossAxisCount: 2,
        mainAxisSpacing: AppSpacing.sm,
        crossAxisSpacing: AppSpacing.sm,
        childCount: notes.length,
        itemBuilder: (context, index) {
          final note = notes[index];
          return NoteCard(
              note: note,
               onTap: () => onTap(note),
               onDelete: () => onDelete(note),
               onToggleFavorite: () => onToggleFavorite(note),
             );
        },
      ),
    );
  }
}
