import 'package:flutter/material.dart';
import 'package:supanotes/shared/widgets/app_popup_menu.dart';

class NotesMoreMenu extends StatelessWidget {
  const NotesMoreMenu({
    required this.isListView,
    required this.onToggleViewMode,
    required this.onLogout,
    required this.onOpenSettings,
    super.key,
  });

  final bool isListView;
  final VoidCallback onToggleViewMode;
  final VoidCallback onLogout;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    void onSelected(String value) {
      switch (value) {
        case 'toggleView':
          onToggleViewMode();
        case 'settings':
          onOpenSettings();
        case 'logout':
          onLogout();
      }
    }

    return AppPopupMenu<String>(
      icon: Icons.more_horiz,
      onSelected: onSelected,
      items: [
        AppPopupMenuItem(
          label: isListView ? 'Ver como galeria' : 'Ver como lista',
          value: 'toggleView',
          appleSymbol: isListView ? 'square.grid.2x2' : 'list.bullet',
          materialIcon: isListView
              ? Icons.grid_view_rounded
              : Icons.list_rounded,
        ),
        const AppPopupMenuItem(
          label: 'Configurações',
          value: 'settings',
          appleSymbol: 'gear',
          materialIcon: Icons.settings_outlined,
        ),
        const AppPopupMenuItem(
          label: 'Sair',
          value: 'logout',
          appleSymbol: 'rectangle.portrait.and.arrow.right',
          materialIcon: Icons.logout,
          isDestructive: true,
        ),
      ],
    );
  }
}
