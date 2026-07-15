import 'package:flutter/material.dart';

import '../../../../shared/theme/app_spacing.dart';
import '../../domain/note_model.dart';
import 'note_list_row.dart';

/// List representation of the notes list.
///
/// Returns the [CustomScrollView] itself (not a sliver). The caller
/// wraps it in a scroll container (e.g. a `RefreshIndicator` +
/// `BouncingScrollPhysics`). [headerSlivers] is prepended to the list
/// so the brain-dump tile and section title can scroll with the
/// notes instead of being pinned above.
class NotesListView extends StatelessWidget {
  const NotesListView({
    super.key,
    required this.notes,
    required this.headerSlivers,
    required this.onTap,
    required this.onDelete,
    required this.onToggleFavorite,
    this.controller,
  });

  final List<NoteModel> notes;
  final List<Widget> headerSlivers;
  final void Function(NoteModel note) onTap;
  final void Function(NoteModel note) onDelete;
  final void Function(NoteModel note) onToggleFavorite;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      controller: controller,
      physics: const AlwaysScrollableScrollPhysics(
        parent: ClampingScrollPhysics(),
      ),
      slivers: [
        ...headerSlivers,
        SliverPadding(
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
        ),
      ],
    );
  }
}
