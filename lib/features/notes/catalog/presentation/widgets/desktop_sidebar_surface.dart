import 'package:flutter/material.dart';

import 'package:supanotes/shared/widgets/desktop_translucent_surface.dart';

/// Presentation surface for the persistent desktop notes navigation.
///
/// Data loading and note actions stay inside [NotesSidebar]. This wrapper only
/// owns the desktop surface boundary so the shell can compose it explicitly.
class DesktopSidebarSurface extends StatelessWidget {
  final Widget child;

  const DesktopSidebarSurface({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: scheme.outlineVariant)),
      ),
      child: DesktopTranslucentSurface(
        key: const ValueKey('desktop-sidebar-surface'),
        color: scheme.surfaceContainerLow,
        child: child,
      ),
    );
  }
}
