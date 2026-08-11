import 'package:flutter/material.dart';

import 'package:supanotes/features/notes/catalog/model/note_model.dart';

/// Decides which note-icon gesture is available for the current note.
///
/// The note list and grid use the same policy so read-only notes cannot drift
/// apart as each surface evolves.
abstract final class NoteIconInteractionPolicy {
  const NoteIconInteractionPolicy._();

  static bool canEditIcon({
    required NoteModel note,
    required VoidCallback? onEditIcon,
  }) {
    return !note.isReadOnly && onEditIcon != null;
  }

  static bool canUseLongPress({
    required NoteModel note,
    required VoidCallback? onEditIcon,
  }) {
    return canEditIcon(note: note, onEditIcon: onEditIcon);
  }
}