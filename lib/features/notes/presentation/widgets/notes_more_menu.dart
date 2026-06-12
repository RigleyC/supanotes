import 'package:flutter/material.dart';

enum _MenuAction { toggleView, settings, logout }

class NotesMoreMenu extends StatelessWidget {
  const NotesMoreMenu({
    super.key,
    required this.isListView,
    required this.onToggleViewMode,
    required this.onLogout,
    required this.onOpenSettings,
  });

  final bool isListView;
  final VoidCallback onToggleViewMode;
  final VoidCallback onLogout;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_MenuAction>(
      icon: const Icon(Icons.more_horiz),
      onSelected: (selection) {
        switch (selection) {
          case _MenuAction.toggleView:
            onToggleViewMode();
          case _MenuAction.settings:
            onOpenSettings();
          case _MenuAction.logout:
            onLogout();
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem<_MenuAction>(
          value: _MenuAction.toggleView,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(isListView ? Icons.grid_view_rounded : Icons.list_rounded),
            title: Text(isListView ? 'Ver como galeria' : 'Ver como lista'),
          ),
        ),
        const PopupMenuItem<_MenuAction>(
          value: _MenuAction.settings,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.settings_outlined),
            title: Text('Configurações'),
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
  }
}
