import 'package:flutter/material.dart';

/// Presentation surface for the persistent desktop notes navigation.
///
/// Data loading and note actions stay inside [NotesSidebar]. This wrapper only
/// owns the desktop surface boundary so the shell can compose it explicitly.
class DesktopSidebarSurface extends StatelessWidget {
  final Widget child;

  const DesktopSidebarSurface({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      key: const ValueKey('desktop-sidebar-surface'),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: child,
    );
  }
}
