import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supanotes/core/utils/app_haptics.dart';

/// The typographic bottom bar shared by the primary app resources.
///
/// Text tabs sit on the left, aligned with the list content, and a single
/// circular primary action sits on the right. The bar has no surface of its
/// own: it floats over the page background, the same on iOS and Android.
class AppNavigationBar extends StatelessWidget {
  const AppNavigationBar({
    required this.currentIndex,
    required this.onDestinationSelected,
    required this.destinations,
    this.onPrimaryAction,
    super.key,
  });

  /// Horizontal inset of the first tab label, shared with list content.
  static const double contentInset = 28;

  /// Gap between the bar and the bottom safe-area edge.
  static const double bottomGap = 34;

  /// Height of the bar's tallest control (the primary action).
  static const double barHeight = 48;

  /// Space kept between the end of a list and the top of the bar.
  static const double contentGap = 16;

  /// Bottom padding a scrollable needs so its last row ends above the bar.
  static double contentBottomPadding(BuildContext context) =>
      MediaQuery.paddingOf(context).bottom + bottomGap + barHeight + contentGap;

  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<AppNavigationDestination> destinations;

  /// Runs the primary action of the selected destination.
  final VoidCallback? onPrimaryAction;

  @override
  Widget build(BuildContext context) {
    final selectedIndex = currentIndex.clamp(0, destinations.length - 1);
    final selected = destinations[selectedIndex];

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          contentInset - _AppNavigationTab.horizontalPadding,
          0,
          20,
          bottomGap,
        ),
        child: SizedBox(
          height: barHeight,
          child: Row(
            children: [
              for (final (index, destination) in destinations.indexed)
                _AppNavigationTab(
                  key: ValueKey('app-navigation-tab-$index'),
                  label: destination.label,
                  selected: index == selectedIndex,
                  onTap: () => onDestinationSelected(index),
                ),
              const Spacer(),
              if (onPrimaryAction != null)
                _AppPrimaryActionButton(
                  tooltip: selected.primaryActionLabel,
                  onPressed: onPrimaryAction!,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppNavigationTab extends StatelessWidget {
  const _AppNavigationTab({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  /// Half of the 20px gap between labels, given to each tap target.
  static const double horizontalPadding = 10;

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final style = (theme.textTheme.bodyLarge ?? const TextStyle()).copyWith(
      fontSize: 17,
      height: 1.2,
      letterSpacing: -0.2,
      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
      color: selected
          ? scheme.onSurface
          : scheme.onSurfaceVariant.withValues(alpha: 0.55),
    );

    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          unawaited(AppHaptics.controlTap());
          onTap();
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: horizontalPadding),
            child: Center(
              widthFactor: 1,
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 150),
                style: style,
                child: Text(label),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AppPrimaryActionButton extends StatelessWidget {
  const _AppPrimaryActionButton({
    required this.tooltip,
    required this.onPressed,
  });

  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: tooltip,
        excludeSemantics: true,
        child: Material(
          key: const ValueKey('app-navigation-primary-action'),
          color: scheme.onSurface,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              unawaited(AppHaptics.controlTap());
              onPressed();
            },
            child: SizedBox.square(
              dimension: AppNavigationBar.barHeight,
              child: Icon(Icons.add_rounded, size: 26, color: scheme.surface),
            ),
          ),
        ),
      ),
    );
  }
}

/// Describes one destination for [AppNavigationBar].
class AppNavigationDestination {
  const AppNavigationDestination({
    required this.label,
    required this.primaryActionLabel,
    required this.onPrimaryAction,
  });

  final String label;

  /// Accessible name of the "+" action while this destination is selected.
  final String primaryActionLabel;

  /// Creates a new item of this destination's resource. Receives a context
  /// above the branch navigators, so sheets and routes open over the bar.
  final void Function(BuildContext context) onPrimaryAction;
}
