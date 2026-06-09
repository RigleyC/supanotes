import 'package:flutter/material.dart';

enum _MenuAction { favoritesOnly, sync, logout }

class NotesMoreMenu extends StatelessWidget {
  const NotesMoreMenu({
    super.key,
    required this.favoritesOnly,
    required this.onToggleFavorites,
    required this.onSync,
    required this.onLogout,
  });

  final bool favoritesOnly;
  final VoidCallback onToggleFavorites;
  final VoidCallback onSync;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.more_horiz),
      onPressed: () => _show(context),
    );
  }

  Future<void> _show(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        box.localToGlobal(Offset(box.size.width - 48, 56), ancestor: overlay),
        box.localToGlobal(
          Offset(box.size.width, 56 + 200),
          ancestor: overlay,
        ),
      ),
      Offset.zero & overlay.size,
    );

    final selection = await showMenu<_MenuAction>(
      context: context,
      position: position,
      items: [
        CheckedPopupMenuItem<_MenuAction>(
          value: _MenuAction.favoritesOnly,
          checked: favoritesOnly,
          child: const Text('Apenas favoritos'),
        ),
        const PopupMenuItem<_MenuAction>(
          value: _MenuAction.sync,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.sync),
            title: Text('Sincronizar agora'),
          ),
        ),
        const PopupMenuItem<_MenuAction>(
          value: _MenuAction.logout,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.logout),
            title: Text('Sair'),
          ),
        ),
      ],
    );

    if (selection == null || !context.mounted) return;
    switch (selection) {
      case _MenuAction.favoritesOnly:
        onToggleFavorites();
      case _MenuAction.sync:
        onSync();
      case _MenuAction.logout:
        onLogout();
    }
  }
}
