import 'package:flutter/material.dart';

import 'package:supanotes/features/notes/catalog/model/note_model.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'note_list_row.dart';

/// List representation of the notes list, anchored to the bottom.
///
/// A reverse [ListView] pins the rows to the bottom edge when they fit the
/// viewport and scrolls lazily when they overflow. Because a reversed list
/// renders the first item at the bottom, the input order is inverted so the
/// visual order stays top-to-bottom. The parent owns the layout (e.g. a
/// [Column]) and provides scroll constraints via [Expanded].
class NotesListView extends StatelessWidget {
  const NotesListView({
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
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
        80 + AppSpacing.sm,
      ),
      itemCount: notes.length,
      itemBuilder: (context, index) {
        final note = notes[notes.length - 1 - index];
        return NoteListRow(
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