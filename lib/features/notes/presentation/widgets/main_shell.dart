import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/widgets/offline_indicator.dart';
import 'quick_capture_fab.dart';

/// Root container for the authenticated home UI.
///
/// The shell is provided by [StatefulShellRoute] — see `app_router.dart`.
/// The bottom navigation delegates to [StatefulNavigationShell.goBranch] so
/// each tab keeps its state (scroll position, stream subscriptions) alive
/// across switches. The shell is the only place that shows the
/// [OfflineIndicator], so the banner is mounted once for the whole
/// authenticated surface.
class MainShell extends ConsumerWidget {
  const MainShell({
    super.key,
    required this.navigationShell,
  });

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = navigationShell.currentIndex;

    return Scaffold(
      body: Column(
        children: [
          const OfflineIndicator(),
          Expanded(child: navigationShell),
        ],
      ),
      floatingActionButton: currentIndex == 0 ? const QuickCaptureFAB() : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: navigationShell.goBranch,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.note_outlined),
            selectedIcon: Icon(Icons.note),
            label: 'Notas',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Chat',
          ),
          NavigationDestination(
            icon: Icon(Icons.search_outlined),
            selectedIcon: Icon(Icons.search),
            label: 'Busca',
          ),
        ],
      ),
    );
  }
}
