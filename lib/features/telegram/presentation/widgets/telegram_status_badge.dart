import 'package:flutter/material.dart';

/// Small visual indicator for the user's Telegram link state.
///
/// Renders a Material 3 [Chip] tinted green when [linked] is `true` and
/// gray otherwise. Intended to be embedded in a Settings tile so the
/// user can see at a glance whether their account is connected, without
/// having to open the full link screen.
class TelegramStatusBadge extends StatelessWidget {
  const TelegramStatusBadge({super.key, required this.linked});

  final bool linked;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final Color background;
    final Color foreground;
    final String label;
    final IconData icon;

    if (linked) {
      background = scheme.tertiaryContainer;
      foreground = scheme.onTertiaryContainer;
      label = 'Conectado';
      icon = Icons.check_circle_outline;
    } else {
      background = scheme.surfaceContainerHighest;
      foreground = scheme.onSurfaceVariant;
      label = 'Não conectado';
      icon = Icons.link_off_outlined;
    }

    return Chip(
      avatar: Icon(icon, size: 18, color: foreground),
      label: Text(label),
      backgroundColor: background,
      labelStyle: TextStyle(color: foreground),
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
