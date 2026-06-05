import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/offline_indicator.dart';
import '../../../tasks/presentation/today_tasks_screen.dart';
import '../notes_list_screen.dart';
import 'quick_capture_fab.dart';

/// Tab index of the in-shell [BottomNavigationBar].
enum _Tab { notes, today, chat, search }

/// Root container for the authenticated home UI.
///
/// The shell is mounted only on the `/home` route — see
/// `app_router.dart`. The bottom navigation is **state-only**: tapping a
/// tab calls `setState(() => _index = tab)`, it does not push a new
/// `GoRouter` location. This keeps each tab's state (scroll position,
/// stream subscriptions) alive across switches, and means there is no
/// need for a `StatefulShellRoute`. The shell is the only place that
/// shows the [OfflineIndicator], so the banner is mounted once for the
/// whole authenticated surface.
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  _Tab _index = _Tab.notes;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const OfflineIndicator(),
          Expanded(
            child: IndexedStack(
              index: _index.index,
              children: const [
                NotesListScreen(),
                TodayTasksScreen(),
                _PlaceholderTab(
                  icon: Icons.chat_bubble_outline,
                  title: 'Chat',
                  subtitle: 'Em breve no FE-7',
                ),
                _PlaceholderTab(
                  icon: Icons.search,
                  title: 'Busca',
                  subtitle: 'Em breve no FE-8',
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: _index == _Tab.notes ? const QuickCaptureFAB() : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index.index,
        onDestinationSelected: (i) => setState(() => _index = _Tab.values[i]),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.note_outlined),
            selectedIcon: Icon(Icons.note),
            label: 'Notas',
          ),
          NavigationDestination(
            icon: Icon(Icons.checklist_outlined),
            selectedIcon: Icon(Icons.checklist),
            label: 'Hoje',
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

class _PlaceholderTab extends StatelessWidget {
  const _PlaceholderTab({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return EmptyState(icon: icon, title: title, subtitle: subtitle);
  }
}
