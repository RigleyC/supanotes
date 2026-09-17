import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// A platform-native navigation bar with a single shared API.
class AppNavigationBar extends StatelessWidget {
  const AppNavigationBar({
    required this.currentIndex,
    required this.onDestinationSelected,
    required this.destinations,
    super.key,
  });

  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<AppNavigationDestination> destinations;

  @override
  Widget build(BuildContext context) {
    final isApple =
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
    if (isApple) {
      return CNTabBar(
        items: [
          for (final destination in destinations)
            CNTabBarItem(
              label: destination.label,
              icon: CNSymbol(destination.appleIcon),
              activeIcon: CNSymbol(destination.appleActiveIcon),
            ),
        ],
        iconSize: 24,
        currentIndex: currentIndex,
        onTap: onDestinationSelected,
        autoHideOnModal: true,
        autoHideOnPageTransition: true,
      );
    }

    return NavigationBar(
      selectedIndex: currentIndex,
      onDestinationSelected: onDestinationSelected,
      destinations: [
        for (final destination in destinations)
          NavigationDestination(
            icon: Icon(destination.icon),
            selectedIcon: Icon(destination.selectedIcon),
            label: destination.label,
          ),
      ],
    );
  }
}

/// Describes one destination for [AppNavigationBar].
class AppNavigationDestination {
  const AppNavigationDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.appleIcon,
    required this.appleActiveIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String appleIcon;
  final String appleActiveIcon;
}
