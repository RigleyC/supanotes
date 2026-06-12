import 'package:flutter/material.dart';

enum _MenuAction { settings, logout }

class NotesMoreMenu extends StatelessWidget {
  const NotesMoreMenu({
    super.key,
    required this.onLogout,
    required this.onOpenSettings,
  });

  final VoidCallback onLogout;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_MenuAction>(
      icon: const Icon(Icons.more_horiz),
      onSelected: (selection) {
        switch (selection) {
          case _MenuAction.settings:
            onOpenSettings();
          case _MenuAction.logout:
            onLogout();
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem<_MenuAction>(
          value: _MenuAction.settings,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.settings_outlined),
            title: Text('Configurações'),
          ),
        ),
        PopupMenuItem<_MenuAction>(
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
