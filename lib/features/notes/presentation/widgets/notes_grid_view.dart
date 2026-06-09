import 'package:cue/cue.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../../../../shared/theme/app_spacing.dart';
import '../../domain/note_model.dart';
import 'note_card.dart';

/// Grid representation of the notes list.
///
/// Returns the [CustomScrollView] itself (not a sliver). The caller
/// wraps it in a scroll container (e.g. a `RefreshIndicator` +
/// `BouncingScrollPhysics`). [headerSlivers] is prepended to the grid
/// so the brain-dump tile and section title can scroll with the
/// notes instead of being pinned above.
class NotesGridView extends StatelessWidget {
  const NotesGridView({
    super.key,
    required this.notes,
    required this.headerSlivers,
    required this.onTap,
    required this.onDelete,
    required this.onToggleFavorite,
  });

  final List<NoteModel> notes;
  final List<Widget> headerSlivers;
  final void Function(NoteModel note) onTap;
  final void Function(NoteModel note) onDelete;
  final void Function(NoteModel note) onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
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
          sliver: SliverMasonryGrid.count(
            crossAxisCount: 2,
            mainAxisSpacing: AppSpacing.sm,
            crossAxisSpacing: AppSpacing.sm,
            childCount: notes.length,
            itemBuilder: (context, index) {
              final note = notes[index];
              return Cue.onMount(
                motion: .smooth(),
                acts: [.fadeIn(), .scale(from: 0.96), .slideY(from: 0.08)],
                child: NoteCard(
                  note: note,
                  onTap: () => onTap(note),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
