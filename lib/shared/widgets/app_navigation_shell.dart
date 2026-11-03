import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supanotes/shared/widgets/app_navigation_bar.dart';

/// The public navigation frame for the two primary app resources.
///
/// The branch pages fill the screen and the typographic [AppNavigationBar]
/// floats over their bottom edge. A short fade in the page color keeps
/// scrolled content from colliding with the bar; pages leave room for it with
/// [AppNavigationBar.contentBottomPadding].
class AppNavigationShell extends StatelessWidget {
  const AppNavigationShell({
    required this.navigationShell,
    required this.destinations,
    super.key,
  });

  final StatefulNavigationShell navigationShell;
  final List<AppNavigationDestination> destinations;

  @override
  Widget build(BuildContext context) {
    final background = Theme.of(context).scaffoldBackgroundColor;
    final barExtent =
        MediaQuery.paddingOf(context).bottom +
        AppNavigationBar.bottomGap +
        AppNavigationBar.barHeight;
    final selected =
        destinations[navigationShell.currentIndex.clamp(
          0,
          destinations.length - 1,
        )];

    return Scaffold(
      // Pages handle the keyboard themselves; the bar stays behind it.
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Positioned.fill(child: navigationShell),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: barExtent + 24,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [background.withValues(alpha: 0), background],
                    stops: const [0, 0.45],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Builder(
              builder: (barContext) => AppNavigationBar(
                currentIndex: navigationShell.currentIndex,
                destinations: destinations,
                onDestinationSelected: (index) {
                  navigationShell.goBranch(
                    index,
                    initialLocation: index == navigationShell.currentIndex,
                  );
                },
                onPrimaryAction: () => selected.onPrimaryAction(barContext),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
