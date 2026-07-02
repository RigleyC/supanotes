/// Reusable [ListTile] used inside the settings screens.
///
/// Three variants are provided as named constructors so feature code
/// reads as "what kind of row is this" rather than "which arguments do
/// I leave null":
///
///   * [SettingsTile.navigation] — leads to another screen; renders a
///     chevron on the right.
///   * [SettingsTile.toggle] — controls a boolean; renders a [Switch].
///   * [SettingsTile.action] — fires a one-shot callback; renders an
///     arbitrary `trailing` widget (typically a button or an icon).
///
/// All three variants share the same icon / title / optional subtitle
/// shape so the visual rhythm is consistent across sections.
library;

import 'package:flutter/material.dart';

import 'package:supanotes/shared/theme/app_spacing.dart';

enum _SettingsTileKind { navigation, toggle, action }

class SettingsTile extends StatelessWidget {
  const SettingsTile.navigation({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.enabled = true,
  }) : _kind = _SettingsTileKind.navigation,
       value = null,
       onChanged = null,
       trailing = null;

  const SettingsTile.toggle({
    super.key,
    required this.icon,
    required this.title,
    required bool this.value,
    required this.onChanged,
    this.subtitle,
    this.enabled = true,
  }) : _kind = _SettingsTileKind.toggle,
       onTap = null,
       trailing = null;

  const SettingsTile.action({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.enabled = true,
  }) : _kind = _SettingsTileKind.action,
       value = null,
       onChanged = null;

  final _SettingsTileKind _kind;
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool enabled;

  /// Used by [SettingsTile.toggle] only.
  final bool? value;

  /// Used by [SettingsTile.toggle] only.
  final ValueChanged<bool>? onChanged;

  /// Used by [SettingsTile.action] only.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final Widget? effectiveTrailing;
    VoidCallback? effectiveOnTap;
    switch (_kind) {
      case _SettingsTileKind.navigation:
        effectiveTrailing = const Icon(Icons.chevron_right);
        effectiveOnTap = enabled ? onTap : null;
        break;
      case _SettingsTileKind.toggle:
        effectiveTrailing = Switch(
          value: value ?? false,
          onChanged: enabled ? onChanged : null,
        );
        // Tapping the whole row also flips the switch — matches platform
        // expectations and keeps the hit target large.
        effectiveOnTap = enabled && onChanged != null
            ? () => onChanged!(!(value ?? false))
            : null;
        break;
      case _SettingsTileKind.action:
        effectiveTrailing = trailing;
        effectiveOnTap = enabled ? onTap : null;
        break;
    }

    return ListTile(
      enabled: enabled,
      leading: Icon(icon, color: scheme.onSurfaceVariant),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: effectiveTrailing,
      onTap: effectiveOnTap,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
    );
  }
}

/// Visually-distinct heading rendered above each group of [SettingsTile]s.
class SettingsSectionHeader extends StatelessWidget {
  const SettingsSectionHeader({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      child: Text(
        title.toUpperCase(),
        style: textTheme.labelSmall?.copyWith(
          color: scheme.primary,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
