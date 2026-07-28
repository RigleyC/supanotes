import 'package:flutter/material.dart';
import 'package:super_context_menu/super_context_menu.dart';

import 'package:supanotes/features/notes/catalog/model/note_model.dart';

/// Shared wrapper for native context menus (right-click / long-press) on notes.
class NoteContextMenuWidget extends StatelessWidget {
  final NoteModel note;
  final VoidCallback onToggleFavorite;
  final VoidCallback onDelete;
  final Widget child;

  const NoteContextMenuWidget({
    super.key,
    required this.note,
    required this.onToggleFavorite,
    required this.onDelete,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ContextMenuWidget(
      menuProvider: (request) {
        return Menu(
          children: [
            MenuAction(
              title: note.favorite ? 'Remover favorito' : 'Favoritar',
              image: MenuImage.icon(
                note.favorite ? Icons.star_border : Icons.star,
              ),
              callback: onToggleFavorite,
            ),
            MenuAction(
              title: 'Excluir nota',
              attributes: const MenuActionAttributes(destructive: true),
              image: MenuImage.icon(Icons.delete_outline),
              callback: onDelete,
            ),
          ],
        );
      },
      child: child,
    );
  }
}
