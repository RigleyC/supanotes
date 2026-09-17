import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supanotes/shared/widgets/app_navigation_bar.dart';

/// The public navigation frame for the two primary app resources.
class AppNavigationShell extends StatelessWidget {
  const AppNavigationShell({
    required this.navigationShell,
    super.key,
  });

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: navigationShell,
      bottomNavigationBar: AppNavigationBar(
        currentIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) {
          navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          );
        },
        destinations: const [
          AppNavigationDestination(
            label: 'Tasks',
            assetIcon: 'assets/icons/navigation_checkbox.svg',
          ),
          AppNavigationDestination(
            label: 'Notas',
            assetIcon: 'assets/icons/navigation_notes.svg',
          ),
        ],
      ),
    );
  }
}
