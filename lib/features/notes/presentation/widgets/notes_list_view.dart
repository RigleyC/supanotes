import 'package:flutter/material.dart';

import '../../../../shared/theme/app_spacing.dart';
import '../../domain/note_model.dart';
import 'note_list_row.dart';

/// List representation of the notes list.
///
/// Returns a [SliverPadding] wrapping a [SliverList] — no [CustomScrollView]
/// of its own. The parent owns the scroll view and any leading slivers.
class NotesListView extends StatelessWidget {
  const NotesListView({
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
      sliver: SliverList.builder(
        itemCount: notes.length,
        itemBuilder: (context, index) {
          final note = notes[index];
          return NoteListRow(
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
