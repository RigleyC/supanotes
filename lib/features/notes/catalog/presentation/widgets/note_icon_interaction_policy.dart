import 'package:flutter/material.dart';

import 'package:supanotes/core/utils/platform_utils.dart';
import 'package:supanotes/features/notes/catalog/model/note_model.dart';

/// Decides which note-icon gesture is available for the current note.
///
/// The note list, grid and sidebar use the same policy so read-only notes and
/// desktop interactions cannot drift apart as each surface evolves.
abstract final class NoteIconInteractionPolicy {
  const NoteIconInteractionPolicy._();

  static bool canEditIcon({
    required NoteModel note,
    required VoidCallback? onEditIcon,
  }) {
    return !note.isReadOnly && onEditIcon != null;
  }

  static bool canUseMobileLongPress({
    required BuildContext context,
    required NoteModel note,
    required VoidCallback? onEditIcon,
  }) {
    return !isDesktopLayout(context) &&
        canEditIcon(note: note, onEditIcon: onEditIcon);
  }

  static bool canUseDesktopContextMenu({
    required BuildContext context,
    required NoteModel note,
    required VoidCallback? onEditIcon,
  }) {
    return isDesktopLayout(context) &&
        canEditIcon(note: note, onEditIcon: onEditIcon);
  }
}
