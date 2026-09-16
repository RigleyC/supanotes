import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
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
    final isIos = PlatformInfo.isIOS;
    return AdaptiveScaffold(
      body: navigationShell,
      bottomNavigationBar: AdaptiveBottomNavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onTap: (index) {
          navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          );
        },
        items: [
          AdaptiveNavigationDestination(
            icon: isIos ? 'checkmark.circle' : Icons.check_box_outlined,
            selectedIcon: isIos ? 'checkmark.circle.fill' : Icons.check_box,
            label: 'Tasks',
          ),
          AdaptiveNavigationDestination(
            icon: isIos ? 'note' : Icons.notes_outlined,
            selectedIcon: isIos ? 'note.fill' : Icons.notes,
            label: 'Notas',
          ),
        ],
      ),
    );
  }
}
