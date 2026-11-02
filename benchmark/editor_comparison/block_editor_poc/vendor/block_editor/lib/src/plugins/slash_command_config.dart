library;

import 'package:flutter/widgets.dart';

import 'block_plugin.dart';

/// Describes the entry a [BlockPlugin] contributes to a trigger-character menu.
///
/// Returned by [BlockPlugin.slashCommandItem]. When null is returned the
/// plugin contributes no menu entry.
///
/// The [trigger] field controls which typed character opens the menu and
/// surfaces this entry. Multiple plugins may register different trigger
/// characters, allowing the same menu infrastructure to serve slash commands,
/// mention lookups, tag insertion, or any other character-triggered flow.
@immutable
final class SlashCommandConfig {
  /// Creates a [SlashCommandConfig].
  ///
  /// [label] is the primary text shown in the menu row.
  ///
  /// [group] is the section name under which this entry appears. Built-in
  /// plugins return fixed group names. External plugins return their chosen
  /// group name. When null the entry appears under a default group.
  ///
  /// [icon] is the leading widget shown beside [label].
  ///
  /// [trigger] is the single character whose input opens the menu and
  /// surfaces this entry. Defaults to `'/'`. A plugin may supply any
  /// single character, such as `'@'` for mentions or `'#'` for tags.
  ///
  /// [description] is optional secondary text shown beneath [label].
  ///
  /// [onSelected] is called when the user confirms this entry.
  const SlashCommandConfig({
    required this.label,
    required this.group,
    required this.icon,
    required this.onSelected,
    this.trigger = '/',
    this.description,
  });

  /// The primary text shown in the menu row.
  final String label;

  /// The section name under which this entry appears in the menu.
  ///
  /// When null the entry falls under a default group.
  final String? group;

  /// The leading widget shown beside [label].
  final Widget icon;

  /// The single character whose input opens the menu and surfaces this entry.
  ///
  /// Defaults to `'/'`. Multiple entries with different trigger characters
  /// may coexist in the same registry.
  final String trigger;

  /// Optional secondary text shown beneath [label].
  final String? description;

  /// Called when the user confirms this slash command entry.
  final void Function() onSelected;

  /// Returns a copy of this config with the given fields replaced.
  ///
  /// To explicitly set [group] or [description] to null, pass
  /// `group: null` or `description: null`. The sentinel-based
  /// implementation correctly distinguishes between omitted and
  /// explicitly-null arguments.
  SlashCommandConfig copyWith({
    String? label,
    Object? group = _sentinel,
    Widget? icon,
    String? trigger,
    Object? description = _sentinel,
    void Function()? onSelected,
  }) {
    return SlashCommandConfig(
      label: label ?? this.label,
      group: group == _sentinel ? this.group : group as String?,
      icon: icon ?? this.icon,
      trigger: trigger ?? this.trigger,
      description: description == _sentinel
          ? this.description
          : description as String?,
      onSelected: onSelected ?? this.onSelected,
    );
  }
}

const Object _sentinel = Object();
