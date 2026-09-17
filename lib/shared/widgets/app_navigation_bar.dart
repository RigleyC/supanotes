import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

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
    final selectedIndex = currentIndex.clamp(0, destinations.length - 1);
    final isApple =
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
    if (isApple) {
      return CNTabBar(
        items: [
          for (final destination in destinations)
            CNTabBarItem(
              label: '',
              imageAsset: CNImageAsset(destination.assetIcon, size: 24),
              activeImageAsset: CNImageAsset(destination.assetIcon, size: 24),
            ),
        ],
        iconSize: 24,
        currentIndex: selectedIndex,
        onTap: onDestinationSelected,
        autoHideOnModal: false,
        autoHideOnPageTransition: false,
      );
    }

    return NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: onDestinationSelected,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
      destinations: [
        for (final destination in destinations)
          NavigationDestination(
            icon: _AssetIcon(asset: destination.assetIcon),
            selectedIcon: _AssetIcon(asset: destination.assetIcon),
            label: destination.label,
          ),
      ],
    );
  }
}

class _AssetIcon extends StatelessWidget {
  const _AssetIcon({required this.asset});

  final String asset;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      asset,
      width: 24,
      height: 24,
      colorFilter: ColorFilter.mode(
        IconTheme.of(context).color ??
            Theme.of(context).colorScheme.onSurfaceVariant,
        BlendMode.srcIn,
      ),
    );
  }
}

/// Describes one destination for [AppNavigationBar].
class AppNavigationDestination {
  const AppNavigationDestination({
    required this.label,
    required this.assetIcon,
  });

  final String label;
  final String assetIcon;
}
