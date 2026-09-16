import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// The public navigation frame for the two primary app resources.
///
/// The [StatefulNavigationShell] owns one navigator per destination, so
/// switching tabs does not discard a note editor or a task sub-route.
class AppNavigationShell extends StatelessWidget {
  const AppNavigationShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        backgroundColor: colorScheme.surface,
        indicatorColor: colorScheme.primaryContainer,
        onDestinationSelected: (index) {
          navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          );
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.check_box_outlined),
            selectedIcon: Icon(Icons.check_box),
            label: 'Tasks',
          ),
          NavigationDestination(
            icon: Icon(Icons.notes_outlined),
            selectedIcon: Icon(Icons.notes),
            label: 'Notas',
          ),
        ],
      ),
    );
  }
}
