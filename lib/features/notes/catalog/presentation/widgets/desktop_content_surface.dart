import 'package:flutter/material.dart';

/// Continuous desktop content surface for the selected note or route child.
///
/// This widget owns only the visual boundary. Routing, note loading, editor
/// sessions, and synchronization remain owned by their existing layers.
class DesktopContentSurface extends StatelessWidget {
  final Widget child;

  const DesktopContentSurface({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      key: const ValueKey('desktop-content-surface'),
      color: Theme.of(context).colorScheme.surface,
      child: child,
    );
  }
}
