import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';

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
    return AdaptivePopupMenuButton.icon<String>(
      icon: PlatformInfo.isIOS26OrHigher() ? 'ellipsis' : Icons.more_horiz,
      onSelected: (index, entry) {
        switch (entry.value) {
          case 'toggleView':
            onToggleViewMode();
          case 'settings':
            onOpenSettings();
          case 'logout':
            onLogout();
        }
      },
      items: [
        AdaptivePopupMenuItem<String>(
          label: isListView ? 'Ver como galeria' : 'Ver como lista',
          icon: PlatformInfo.isIOS26OrHigher()
              ? (isListView ? 'square.grid.2x2' : 'list.bullet')
              : (isListView ? Icons.grid_view_rounded : Icons.list_rounded),
          value: 'toggleView',
        ),
        AdaptivePopupMenuItem<String>(
          label: 'Configurações',
          icon: PlatformInfo.isIOS26OrHigher()
              ? 'gear'
              : Icons.settings_outlined,
          value: 'settings',
        ),
        AdaptivePopupMenuItem<String>(
          label: 'Sair',
          icon: PlatformInfo.isIOS26OrHigher()
              ? 'rectangle.portrait.and.arrow.right'
              : Icons.logout,
          value: 'logout',
        ),
      ],
    );
  }
}
